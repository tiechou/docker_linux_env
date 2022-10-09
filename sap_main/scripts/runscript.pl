#!/usr/local/bin/perl 

use strict;
use POSIX;
use warnings;
use Time::HiRes;
use BSD::Resource;
use Getopt::Std;
use File::Basename;
use XML::Simple;
use Cwd 'realpath';
use Data::Dumper;

my $COREMAILADDR='';
my $SMSRECEIVER='';
my $PRODNAME='';
my $HOMEDIR;
my $CONTINUEFLAG=1;
my $ROLENAME;
my $SUSER;
my $LOGFILE;
my $BINPATH;
my $BINFILE;
my $BEFORESCRIPT='';
my $CONFFILE;
my $CONFIG;
my $LOGCONFFILE="";
my $ASDAEMON;
my %opts;
my $EXPORTPATH="LD_LIBRARY_PATH=/home/admin/sp/lib:/home/admin/sp/sp_worker/lib";
my $log_file = " ";
my $PRELOADFILE;
my $CMD_OP = "start";
my $CHILD_PID = -1;

getopts('d:n:c:p:l:k:b', \%opts);

if( defined $opts{k} && !($opts{k} eq "") ) {
	$CMD_OP=$opts{k}
}
if( !($CMD_OP eq "start" || $CMD_OP eq "stop") ) {
	usage();
	exit(1);
}

$BINPATH=dirname(realpath($0));
if( !defined $opts{d} ) {
	$HOMEDIR=realpath("$BINPATH/..");
} else {
	$HOMEDIR=realpath($opts{d});
}
$BINPATH="$HOMEDIR/bin";
$CONFIG="$HOMEDIR/conf/runscript.xml";

$ROLENAME=$opts{n};

if( ! -e $CONFIG) {
	print "$CONFIG not exist.\n";
	exit(1)
} else {
	my $xs1 = XML::Simple->new();
	my $doc = $xs1->XMLin($CONFIG);
	$PRODNAME = $doc->{'prod'};
	$COREMAILADDR = $doc->{'alert'}->{'email'};
	$SMSRECEIVER = $doc->{'alert'}->{'phone'};
	my $service = $doc->{'services'} -> {'service'};
	my $app = $service->{$ROLENAME};
       	if (!$app) {
               print "can not get app detail from config.\n";
               exit(1);
       	}
	$BINFILE = $app->{'bin'};		
	$CONFFILE = $app->{'config'};
	$LOGCONFFILE = $app->{'log'};
}

$SUSER=$ROLENAME;

$LOGFILE="$HOMEDIR/logs/$SUSER.swap.log";
if( !-f $BINFILE ) {
	print STDERR "binary file $BINFILE dont exists.\n";
	exit(1);
}
if( !-x $BINFILE ) {
	print STDERR "binary file $BINFILE is not executable.\n";
	exit(1);
}
if( defined $opts{c} ) {
	$CONFFILE=$opts{c};
}
if( !-f $CONFFILE ) {
	print STDERR "config file $CONFFILE dont exists.\n";
	exit(1);
}
if( defined $opts{l} ) {
	$LOGCONFFILE=$opts{l};
}

if( defined $opts{p} ) {
	$PRELOADFILE=$opts{p};
	if (!-f $PRELOADFILE) {
	    print STDERR "pre-load file dont exists.\n";
	    $PRELOADFILE="/dev/null";
	}
} else {
	$PRELOADFILE="/dev/null";
}

if( defined $opts{b} ) {
	$ASDAEMON = 1;
} else {
	$ASDAEMON = 0;
}

$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = \&quit_handler;
sub quit_handler {
    my $sig = shift;
    if ($CONTINUEFLAG == 1)
    {
        $CONTINUEFLAG = 0;
        print "receive signal $sig, exiting..\n";
        if ($CHILD_PID > 0)
        {
            kill TERM=>$CHILD_PID;
        }
    }
}

#exportPath();
if( $CMD_OP eq "stop" ) {
	stopServer();
	exit(0);
}

if ($COREMAILADDR eq "")
{
    print "no email to send alert!\n";
}

run_searcher();

sub usage
{
	print STDERR "Usage: runscript.pl -n [role] -d <home_dir> -c <conf_file> -l <log_conf_file> -k [start|stop] [-b]\n";
	print STDERR "  -n: which server to start\n";
	print STDERR "  -d: home dir\n";
	print STDERR "  -c: server.cfg file\n";
	print STDERR "  -l: log config file\n";
	print STDERR "  -p: preload file\n";
	print STDERR "  -b: whether run as daemon\n\n";
}

sub stopServer
{
    my $pid = get_running_pid();
    if ($pid eq "")
    {
        print "not running\n";
        exit 0
    }

    `kill "$pid"`;

	my $STOPCMD=" $EXPORTPATH $BINFILE -c $CONFFILE";
	$STOPCMD .=" -k stop";

	my $stopchildpid=open(F,"|-",$STOPCMD);
	waitpid($stopchildpid, 0);
    close F;

	my $STOP_MSG = "Receive Stop CMD = $STOPCMD   pid = $stopchildpid\n";
	LOG($STOP_MSG);
}

sub get_running_pid()
{
    my $find_cmd = "ps wwu -C runscript.pl | egrep -- '-n[ ]*$ROLENAME' | egrep -- '-k[ ]*start'";
    $find_cmd .= ' | fgrep -v grep | awk "{print \$2}"';
    my $pid = `$find_cmd`;
    chop($pid);
    return $pid;
}

sub run_searcher
{
	# clean old files. leave no more than max_files. don't take more than max_size bytes. There is a cron job on prod nodes to delete old idpd.output* files
	my %clean=
	(
		$LOGFILE             =>{max_files=> 100, max_size=> 1000*(1<<20)},
		"core."              =>{max_files=>   1, max_size=>   10*(1<<01)},
		"found.core"         =>{max_files=>  10, max_size=>   10*(1<<30)},
		"found.backtrace"    =>{max_files=>  20, max_size=>  100*(1<<20)},
		"found.strings"      =>{max_files=>  20, max_size=>  100*(1<<20)},
		"crashlog"           =>{max_files=>  30, max_size=>    1*(1<<20)},
		"dmalloc.logfile"    =>{max_files=>  20, max_size=>  100*(1<<20)},
	);

    my $ps_count;
	# exit if crash rate is exceeded i.e. exit if crashes more than "crashes" times in "time" seconds
	my @max_crash_rate=
	(
		{crashes=> 10, time=>5*60}
	);

    my $NOEXP_CMD="$BINFILE -c $CONFFILE";
	if (!( $LOGCONFFILE eq "" )) {
		$NOEXP_CMD .= " -l $LOGCONFFILE";
	}
	$NOEXP_CMD .= " -k restart";

    my $pid = get_running_pid();
    if (!($pid eq "" || $pid eq $$))
    {
        my @pid_array=split(/\n/, $pid);
        my $ppid=getppid();
        my $length=@pid_array;
        if (!($length == 2 && (($pid_array[0] eq $$ && $pid_array[1] eq $ppid) 
                || ($pid_array[1] eq $$ && $pid_array[0] eq $ppid))))
        {
            print "runscript.pl already running!\n";
            exit 0;
        }
    }
	my $SECMD="$EXPORTPATH $NOEXP_CMD";

    $ps_count = `ps auxww | fgrep '$NOEXP_CMD' | fgrep -v grep | wc -l`;
    chop($ps_count);
    if ($ps_count gt 0)
    {
        print "$NOEXP_CMD already running!\n";
        exit 0;
    }

	## done with configuration
	if( $ASDAEMON == 1 ) {
		print "daemonizing myself $0\n";

		chdir '/' or die "Can't chdir to /: $!";
		open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
		open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
		open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";
		defined(my $pid = fork)   or die "Can't fork: $!";
		exit 0 if $pid;
		POSIX::setsid or die "Can't start a new session: $!";
	}
	$|=1;
	open STDERR,">&STDOUT";
	chdir $HOMEDIR or die "chdir $HOMEDIR: $!";
	{
		my ($soft,$hard)= getrlimit(RLIMIT_CORE());
		$soft=-1;
		setrlimit(RLIMIT_CORE(), $soft, $hard) or die "Couldn't setrlimit: $!\n";
		($soft,$hard)= getrlimit(RLIMIT_NOFILE());
		$soft=65535;
		setrlimit(RLIMIT_NOFILE(), $soft, $hard) or die "Couldn't setrlimit: $!\n";
	}
	run_loop(SECMD=>$SECMD,clean=>\%clean,max_crash_rate=>\@max_crash_rate);
}

#sub run_loop in 7 lines:
#  while(1)
#    cleanup old logs
#    exit if crash limit exceeded
#    start secmd in background
#    wait for secmd to finish
#    kill previous save core process
#    save core in background
#
#    at any given time we will have no more than 1 runscript, 1 secmd and 1 save_core processes.
sub run_loop
{
	my %cfg=@_;

	my $HOST=`uname -n`;
	chomp $HOST;
	$HOST||="unknown";

	my @runs;

	my $core_dumper_pid;
	my $zapmws=0;
	while($CONTINUEFLAG)
	{
		for my $cr (@{$cfg{max_crash_rate}})
		{
			next if @runs < $cr->{crashes};
			my $i=$cr->{crashes};
			my $t=time-$runs[$i-1];
			next if $t>=$cr->{time};
			LOG("Crash limit violated in $t seconds. Limit is $cr->{crashes} in $cr->{time} seconds. Exit!\n");

            sleep(3);
            last;
# $CONTINUEFLAG=0;
# $zapmws=1;
		}

        my $Restart_MSG = "Receive Restart CMD = $cfg{SECMD}\n";
        LOG($Restart_MSG);
		last if !$CONTINUEFLAG;

		my $start_time=time;
		unshift @runs, $start_time;
		pop @runs if @runs>1000; # don't track more than 1000 failures

		# run SECMD in background
		LOG("running $cfg{SECMD}");
        if(!($BEFORESCRIPT eq ''))
        {
            LOG("running script: $BEFORESCRIPT");
            `$BEFORESCRIPT`;
        }

		if(!($CHILD_PID=open(F,"|-",$cfg{SECMD})))
		{
			LOG("failed to execute: $!");
		}
		else
		{
			my $status;
			my $t;
			#wait for SECMD to finish. watch for save_core to avoid zombie
			while(1)
			{
			    loadFile() if(($cfg{SECMD} =~ /start/) && ($cfg{SECMD} =~ /searcher/));
				my $pid=waitpid(-1,0);
				if($pid==$CHILD_PID)
				{
					$status=$?;
					$t=time-$start_time;
					close F;
					LOG("process $CHILD_PID finished in $t seconds");
					last;
				}
				elsif(defined $core_dumper_pid && $pid==$core_dumper_pid)
				{
					LOG("save core $core_dumper_pid finished");
					$core_dumper_pid=undef;
				}
				else
				{
					die "$pid";
				}
			}

			if($status & 127)
			{
				my $is_core_dump= ($status & 128);
				my $signal= $status & 127;
				LOG("died with signal $signal");
				if( $is_core_dump)
				{
					LOG("core dump is generated");
					if(1) # save core in background
					{
						#kill previous copy of save core
						if(defined $core_dumper_pid)
						{
							LOG("killing previous save core $core_dumper_pid");
							kill HUP=>$core_dumper_pid;
							waitpid($core_dumper_pid,0);
							LOG("save core $core_dumper_pid finished");
							$core_dumper_pid=undef;
						}
						defined($core_dumper_pid = fork) or die "Can't fork: $!";
						if (!$core_dumper_pid)
						{
							save_core();
							exit;
						}
					}
					else #save core
					{
						save_core();
					}
				}
			}
			else
			{
				my $exit_code=$status >> 8;
				LOG("exit code: $exit_code");
			}
		}
		sleep(5); #don't loop faster than 60 times/min
	}

	if(defined $core_dumper_pid)
	{
		if($zapmws)
		{
			LOG("killing previous save core $core_dumper_pid");
			kill HUP=>$core_dumper_pid;
		}
		waitpid($core_dumper_pid,0);
		LOG("save core $core_dumper_pid finished");
		$core_dumper_pid=undef;
	}
}

sub cleanup
{
	my ($max_files,$max_space,$glob_pattern)=@_;

	my @files=glob($glob_pattern);

	my %files_by_mtime;

	for my $fname (@files)
	{
		my ($size,$mtime)=(stat $fname)[7,9];
		$files_by_mtime{$mtime}={name=>$fname,size=>$size};
	}
	my $files_to_keep=0;
	my $size_to_keep=0;
	my @files_to_delete;
	for my $mtime (reverse sort keys %files_by_mtime)
	{
		if(!$files_to_keep || # keep at least one file
			(($files_to_keep< $max_files || !$max_files) &&
				($size_to_keep+$files_by_mtime{$mtime}{size}<=$max_space || !$max_space)))
		{
			$files_to_keep++;
			$size_to_keep+=$files_by_mtime{$mtime}{size};
			next;
		}
		unshift @files_to_delete,$files_by_mtime{$mtime}{name};
	}
	for(@files_to_delete)
	{
		print "unlink $_\n";
		unlink $_;
	}
}

sub LOG
{
	my ($msg)=@_;
	die if ! defined $msg;
	my $logmsg=scalar(localtime)." $msg\n";
	print STDERR $logmsg;
	open LOG,">>$LOGFILE" or die "open $LOGFILE: $!";
	print LOG $logmsg;
	close LOG;
}

sub save_core
{
	my $hup_received=0;
	local $SIG{'HUP'}  = sub {print STDERR "got HUP\n"; $hup_received=1};

	my $HOST=`uname -n`;
	chomp $HOST;
	$HOST||="unknown";

	my $date = `date '+%Y-%m-%d_%H%M%S'`; chomp $date;

	my $data="\n";
	$data.="Date: $date\n";
	$data.= "Host: $HOST\n";

	my $core;
	my $corename = "$SUSER.found.core.$HOST.$date";
	my $btname = "$SUSER.found.backtrace.$HOST.$date";

	my $corefile = `/sbin/sysctl kernel.core_pattern 2> /dev/null | awk -F"=" '{print \$2;}' | sed -e 's/ //g'`;
	chomp $corefile;
	$corefile =~ s/\%e/$SUSER/g;
	$corefile =~ s/\%p/$CHILD_PID/g;
	$corefile =~ s/\%[a-zA-Z]/\*/g;
	my @cores = glob($corefile);
	#wait for core start being written
	for (0..4)
	{
		sleep 1;
		if( $corefile eq "" ) {
			$core = "core", last if -f "core";
			$core = "core.$CHILD_PID", last if -f "core.$CHILD_PID";
		} elsif( @cores == 0 ) {
			last;
		} else {
			my $gotcore;
			for (@cores) {
				$gotcore = $_, last if -f $_;
			}
			$core = $gotcore, last if defined $gotcore;
		}
		sleep 1;

        # force to empty
        $corefile = '';
	}
	LOG("corefile: $corefile");
	if(!defined $core)
	{
		$data.="No core is created\n";
	}
	else
	{
		# wait until core creation is completed
		my $mtime = (stat($core))[9];
		while(1)
		{
			sleep 3;
			my $newtime = (stat($core))[9];
			last if $mtime == $newtime;
			$mtime = $newtime;
		}
		my $pwd = `pwd`; chomp $pwd;
		my $rsync=$pwd;
		$rsync =~ s#$HOMEDIR#::$PRODNAME#;
		$rsync = "${HOST}${rsync}";

		# Fix permissions on the core
		rename $core, "found.core" or $data.="rename $core found.core:$!";
		rename "found.core", $corename or $data.="rename found.core $corename:$!";

		# backtrace data
        my $gdb_cmd_filename='/tmp/.bt.gdb';
		if(open(BT,">$gdb_cmd_filename"))
		{
			print BT "bt\n";
			close BT;
		}
		`gdb --batch --command $gdb_cmd_filename --quiet $BINFILE $corename >$btname 2>&1`;
        unlink $gdb_cmd_filename;

		my $btdata='';
		if (open(BT,"<$btname"))
		{
			while(<BT>)
			{
				/^Reading symbols from/ or /^Loaded symbols for/ or /^\[New process/ or $btdata.=$_;
			}
		}
        close BT;

		$data.="pwd: $pwd\n";
		$data.="$rsync/$corename\n";
		$data.="$rsync/$btname\n";
        #$data.="\n";
        #$data.="Warning: Do not copy the core file.\n";
        #$data.=" (or at least copy using  rsync --inkt-send-safe)\n";
        #$data.="\n";
		$data.=$btdata;
		$data.="\n";
	}

	# kernel log
	{
		$data.="End of kernel log / dmesg:\n";
		$data.="\n";
		if(-f '/var/log/kernel.log')
		{
			$data.=`tail -30 /var/log/kernel.log`;
		}
		else
		{
			$data.=`dmesg | tail -30`;
		}
	}

	# send email
	for(
		"| mail -s '[$PRODNAME] [$ROLENAME] core alert' $COREMAILADDR",
		">crashlog.${HOST}_${date}",
	)
	{
		open F,$_;
		print F $data;
		close F;
	}

    if ($SMSRECEIVER ne '')
    {
       `echo '! runscript $SMSRECEIVER [$PRODNAME] [$ROLENAME] core alert' | nc audi8.cm6 44444`;
    }
}

#sub exportPath
#{
#    my $exportfile = "$HOMEDIR/etc/export.conf";
#    my $currexport = "";
#    $currexport = $ENV{'LD_LIBRARY_PATH'} unless $ENV{'LD_LIBRARY_PATH'} eq "";
#    my $awslib;
#    my $poollib;
#
#    open INPUT, "<$exportfile";
#    while(<INPUT>){
#	chomp;
#	next if $_ eq "";
#	my ($name ,$value) = split(/:/, $_);
#	$awslib = $value if $name =~ /awslib/;
#	$poollib = $value if $name =~ /poollib/;
#    }
#    close INPUT;
#    
#    if( $awslib eq "" and $poollib eq ""){
#	print STDERR "aws/mempool so library path may be not configured";
#    }
#    $currexport .= ":$awslib" unless ($currexport =~  /aws/);
#    $currexport .= ":$poollib" unless ($currexport =~  /pool/);
#    $currexport .= ":$BINPATH" unless ($currexport =~  /$BINPATH/);
#    $EXPORTPATH = " LD_LIBRARY_PATH=$currexport";
#
#}

sub getLogFile
{
    my $findTag = 0;
    my @tag;
    my $line;
    open CONFIG, "<$CONFFILE" or die("can open configure file or log rotate!");
    while(<CONFIG>){
	chomp;
	next if $_ eq "";
	$line = $_;
	$findTag = 1 if ($line =~ /<$opts{n}>/);
	if($findTag == 1 && $line =~ /log_file/){
	    my @tag = split(/=/, $line);
	    $log_file = $tag[1];
	    last;
	}
    }
    close CONFIG;
}

sub loadFile
{
    return if $PRELOADFILE eq "/dev/null";
    my $error_log;
    my $line;
	if($LOGCONFFILE eq ""){
		getLogFile();
	}else{
		$log_file = $LOGCONFFILE;
	}
    open CONFIG, "<$log_file" or die("can open configure file !");
    while(<CONFIG>){
        chomp;
        next if $_ eq "";
        $line = $_;
        if($line =~ /rootAppender.fileName/){
	    my @arr = split(/=/, $line);
	    $error_log = $arr[1];
	    last;
        }
    }
    close CONFIG;
    while(1){
        `tail -1 $error_log|grep 'search server starting'`;
        my $status = $?;
        print $status;
        last if $status == 0;
    }

    open INPUT, "<$PRELOADFILE";
    while(<INPUT>){
        chomp;
        next if $_ eq "";
        print "load file: ".$_."..........\n";
        `cat $_ > /dev/null 2>&1`;
    }
    close INPUT;
}
