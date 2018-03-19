#!/usr/bin/perl
#
# package for the protocol of cytrone 0.X .
# the protocol is undocumented.  however, it was made over HTTP.
#   by k-chinen, CROND, JAIST.
#
package cy0;

use Exporter qw(import);

use strict;
use POSIX qw(strftime);
use LWP::UserAgent;
use HTTP::Request;

use Sys::Syslog;
use Sys::Syslog qw(:standard :macros);

use threads;
use threads::shared;
use Thread::Queue;

our @EXPORT = qw(cy0_trlist cy0_aclist cy0_example cy0_create cy0_end cy0_nodebug cy0_debug cy0_openlog $cy0_eq);

my $debug = 0;
my $cy0_seq = int(rand(100));

our $cy0_eq = new Thread::Queue;

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

sub cy0_trlist {
    my ($host, $port, $lang, $user) = @_;
    my $url;
    my $ua;
    my $res;

    $url = "http://".$host.":".$port."/";

    my %form;
    $form{"action"} = "fetch_content";
    $form{"lang"} = $lang;
    $form{"user"} = $user;

    $ua = LWP::UserAgent->new;
    $res = $ua->post($url, \%form);

    return $res;
}

sub cy0_aclist {
    my ($host, $port, $lang, $user) = @_;
    my $url;
    my $ua;
    my $res;

    $url = "http://".$host.":".$port."/";

    my %form;
    $form{"action"} = "get_sessions";
    $form{"lang"} = $lang;
    $form{"user"} = $user;

    $ua = LWP::UserAgent->new;
    $res = $ua->post($url, \%form);

    return $res;
}

sub cy0_example {
    my ($host, $port, $lang, $user) = @_;
    my $url;
    my $ua;
    my $res;

    $url = "http://".$host.":".$port."/";

    my %form;
    $form{"action"} = "get_configurations";
    $form{"lang"} = $lang;
    $form{"user"} = $user;

    $ua = LWP::UserAgent->new;
    $res = $ua->post($url, \%form);

    return $res;
}

sub _base {
    my ($conn, $lmsg, $majorid, $minorid, $xparam, $host, $port, $xform) = @_;

    my $cparam;
    $cparam = join(":", @{ $xparam } );
    my %form = %{ $xform }; 
    my $url;
    my $ua;
    my $res;
    my $ts;
    my $te;
    my $tk;

    $url = "http://".$host.":".$port."/";

    if($debug) {
            printf "    %-8s %s\n", "#name", "value";
        foreach my $k (keys %form) {
            printf "    %-8s %s\n", $k, $form{$k};
        }
    }

    $ua = LWP::UserAgent->new;
    $ua->timeout(3600); # 1 hour

    _info("INFO _base START $majorid $minorid $cparam");
    $ts = time;
    $res = $ua->post($url, \%form);
    $te = time;
    _info("INFO _base END   $majorid $minorid");

    $tk = $te - $ts;
    _notice("TAKES _base elap $majorid $minorid $cparam $tk");

#sleep rand(17)+3

    $conn->send_utf8($lmsg." ".$res->content);

    $cy0_eq->enqueue("CHANGE $majorid $minorid");

    threads->detach();

    return $res;
}

sub cy0_create {
    my ($conn, $lmsg, $qid,
        $host, $port, $lang, $user, $type, $scenario, $level, $count) = @_;

    $cy0_seq++;

    my @param;
    @param = ($count);

    my %form;
    $form{"action"} = "create_training";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"type"} = $type;
    $form{"scenario"} = $scenario;
    $form{"level"} = $level;
    $form{"count"} = $count;

    my $thr = threads->create(\&_base,
        $conn, $lmsg, $qid, $cy0_seq, \@param, $host, $port, \%form);

    $conn->send_utf8("NOP 2 create");

    return 0;
}

sub cy0_end {
    my ($conn, $lmsg, $qid,
         $host, $port, $lang, $user, $rangeid) = @_;
    my $url;
    my $ua;
    my $res;

    $cy0_seq++;

    my @param;
    @param = ();

    my %form;
    $form{"action"} = "end_training";
    $form{"lang"} = $lang;
    $form{"user"} = $user;
    $form{"range_id"} = $rangeid;

    my $thr = threads->create(\&_base,
        $conn, $lmsg, $qid, $cy0_seq, \@param, $host, $port, \%form);

    $conn->send_utf8("NOP 2 end");

    return 0;
}


sub cy0_nodebug {
    $debug = 0;
}

sub cy0_debug {
    $debug = 1;
}

sub cy0_openlog {
#    openlog('cy0', '', 'users');
    syslog('info', "START");
}

1;
