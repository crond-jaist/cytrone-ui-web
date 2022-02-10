#!/usr/bin/perl
#
# package for the protocol of cytrone 0.X .
# the protocol is undocumented.  however, it was made over HTTP.
#   by k-chinen, CROND, JAIST.
#
package cy1;

use Exporter qw(import);

use strict;
use POSIX qw(strftime);
use LWP::UserAgent;
#use HTTP::Request;
#use Net::SSLeay;
#use Crypt::SSLeay;
#use IO::Socket::SSL;

use URI::Escape;
use JSON;

use Sys::Syslog;
use Sys::Syslog qw(:standard :macros);

use threads;
use threads::shared;
use Thread::Queue;

use Encode qw(decode_utf8);

our @EXPORT = qw(cy1_trlist cy1_aclist cy1_example cy1_create cy1_end cy1_nodebug cy1_debug cy1_openlog cy1_useHTTP cy1_useHTTPS $cy1_eq);

my $debug = 0;
my $cy1_seq = int(rand(100));

my $proto = "http://";

sub cy1_useHTTP {
    $proto = "http://";
}

sub cy1_useHTTPS {
    $proto = "https://";
}



our $cy1_eq = new Thread::Queue;

# debug message procedures
sub _info {
    my($msg) = @_;
    syslog(LOG_INFO, $msg);
    print ";".$msg."\n";
}

sub _notice {
    my($msg) = @_;
    syslog(LOG_NOTICE, $msg);
    print $msg."\n";
}

sub cy1_trlist {
    my ($host, $port, $lang, $user, $passwd) = @_;
    my $url;
    my $ua;
    my $res;

    $url = $proto.$host.":".$port."/";
#print STDERR "cy1_trlist: $url\n";

    my %form;
    $form{"action"} = "fetch_content";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"password"} = $passwd;

    $ua = LWP::UserAgent->new;
    $res = $ua->post($url, \%form);

    if($debug) {
	print "DEBUG: cy1_trlist(): Response content: " . $res->content . "\n";
    }
    return $res;
}

sub cy1_aclist {
    my ($host, $port, $lang, $user, $passwd) = @_;
    my $url;
    my $ua;
    my $res;

    $url = $proto.$host.":".$port."/";

    my %form;
    $form{"action"} = "get_sessions";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"password"} = $passwd;

    $ua = LWP::UserAgent->new;
    $res = $ua->post($url, \%form);

    return $res;
}

sub cy1_example {
    my ($host, $port, $lang, $user, $passwd) = @_;
    my $url;
    my $ua;
    my $res;

    $url = $proto.$host.":".$port."/";

    my %form;
    $form{"action"} = "get_configurations";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"password"} = $passwd;

    $ua = LWP::UserAgent->new;
    $res = $ua->post($url, \%form);

    return $res;
}

sub _base {
    my ($pmode, $conn, $lmsg, $majorid, $minorid, $xparam, $host, $port, $xform) = @_;

    my $cparam;
    $cparam = join(":", @{ $xparam } );
    my %form = %{ $xform }; 
    my $url;
    my $ua;
    my $res;
    my $ts;
    my $te;
    my $tk;
    my $rid;
    my $sid;

    $rid = -1;
    $sid  = -1;

	if($cparam eq '') {
		$cparam = ":";
	}
	if($pmode eq '') {
		$pmode = "_";
	}

    $url = $proto.$host.":".$port."/";

    if($debug) {
            printf "    %-8s %s\n", "#name", "value";
        foreach my $k (keys %form) {
            printf "    %-8s %s\n", $k, $form{$k};
        }
    }

        foreach my $k (keys %form) {
			if($k eq 'range_id') {
				$rid = $form{$k};
			}
        }

    $ua = LWP::UserAgent->new;
    $ua->timeout(3600); # 1 hour

    _info("INFO _base $pmode START $majorid $minorid $cparam");
    $ts = time;
    # Special handling for fields that could contain Japanese characters,
    # since otherwise Python side doesn't handle them correctly
    $form{'type'}=decode_utf8($form{'type'});
    $form{'scenario'}=decode_utf8($form{'scenario'});
    $form{'level'}=decode_utf8($form{'level'});
    $res = $ua->post($url, \%form);
    $te = time;
    _info("INFO _base $pmode END   $majorid $minorid");

    $tk = $te - $ts;
#    _notice("TAKES _base $pmode elap $majorid $minorid $cparam $tk");

#print STDERR "---B\n";
#print STDERR $res->content;
#print STDERR "---M\n";
#print STDERR uri_unescape($res->content);
#print STDERR "---E\n";


#### seek session-id
# 			...Training Session #1...
#

    my $cal = from_json($res->content);
    foreach my $x ( @{$cal} ) {
#	print "x |$x|\n";
	my %y;
	%y = %{ $x };
	
#	foreach my $k (keys %y) {
#		print "$k |".$y{$k}."|\n";
#	}
	
	
	if(defined $y{"message"}) {
	    my $rmsg = $y{"message"};
#print "rmsg 0 |$rmsg|\n";
	    if($rmsg ne '') {
#print "rmsg 1 |$rmsg|\n";
		my $cmsg = uri_unescape($rmsg);
#print "cmsg 0 |$cmsg|\n";
		if($cmsg =~ /Training Session #(\d+)\b/i) {
		    $sid = $1;
#print "sid    |$sid|\n";
  	    	}
	    }
        }
    }

    _notice("INFO _base $pmode $sid $rid\n");
	if($pmode eq 'C') {
    	_notice("TAKES _base $pmode elap $majorid $minorid $cparam $tk $sid");
	}
	if($pmode eq 'E') {
    	_notice("TAKES _base $pmode elap $majorid $minorid $cparam $tk $rid");
	}

#sleep rand(17)+3

    $conn->send_utf8($lmsg." ".$res->content);

    $cy1_eq->enqueue("CHANGE $majorid $minorid");

    threads->detach();

    return $res;
}

sub cy1_create {
    my ($conn, $lmsg, $qid,
        $host, $port, $lang, $user, $passwd,
		$type, $scenario, $level, $count) = @_;

    $cy1_seq++;

    my @param;
    @param = ($count);

    my %form;
    $form{"action"} = "create_training";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"password"} = $passwd;
    $form{"type"} = $type;
    $form{"scenario"} = $scenario;
    $form{"level"} = $level;
    $form{"count"} = $count;

    my $thr = threads->create(\&_base, 'C',
        $conn, $lmsg, $qid, $cy1_seq, \@param, $host, $port, \%form);

    $conn->send_utf8("NOP 2 create");

    return 0;
}

sub cy1_end {
    my ($conn, $lmsg, $qid,
        $host, $port, $lang, $user, $passwd,
		$rangeid) = @_;
    my $url;
    my $ua;
    my $res;

    $cy1_seq++;

    my @param;
    @param = ();

    my %form;
    $form{"action"} = "end_training";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"password"} = $passwd;
    $form{"range_id"} = $rangeid;

    my $thr = threads->create(\&_base, 'E',
        $conn, $lmsg, $qid, $cy1_seq, \@param, $host, $port, \%form);

    $conn->send_utf8("NOP 2 end");

    return 0;
}


sub cy1_nodebug {
    $debug = 0;
}

sub cy1_debug {
    $debug = 1;
}

sub cy1_openlog {
#    openlog('cy1', '', 'users');
    syslog('info', "START");
}

1;
