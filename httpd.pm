#
# simple HTTP daemon functions
#   by k-chinen, CROND, JAIST
#
use Exporter;

package httpd;

use strict;

use threads;
use threads::shared;
use Thread::Queue;

use Digest::MD5 qw( md5_hex ) ;

use HTTP::Daemon;
use HTTP::Status;

use Sys::Syslog qw(:standard :macros);

my $debug_httpd = 0;
my $debug_httpd_auth = 0;

my $fc = 0;

my %convdict = ("ping"=>"PONG");

sub conv {
    my($im) = @_;
    my $om = "";
    if($debug_httpd) {
        print "im |$im|\n";
    }
    if($im =~ /\@\@\{(\S+)\}/) {
        $om = $convdict{$1};
    }
    return $om;
}

sub send_file_wconv {
    my($cc, $fname, $selfurl, $wsurl) = @_;

    $convdict{"httpurl"} = $selfurl;
    $convdict{"wsurl"}   = $wsurl;

    if($cc->antique_client) {
    }
    else {
        if($debug_httpd) {
            print "fname $fname\n";
        }
        open(F, "<$fname") || die;

#       syslog(LOG_INFO, "HTTPD SEND $name OK");
#       syslog(LOG_INFO, "HTTPD SEND ".$rq->url->path." OK");

        my $line;
        my @rs;
        my $cont;
        $cont = "";
        while(<F>) {
            $line = $_;
#            print $line;
            $line =~ s#(\@\@\{\S+\})#&conv($1)#ge;
            if(/"http:\/\//) {
                $line =~ s#"http:.*js"#"${selfurl}vis.js"#g;
            }
            if(/'ws:\/\//) {
                $line =~ s#'ws:.*'#'${wsurl}'#g;
            }
            $cont .= $line;
        }
        my $res;
        $res = HTTP::Response->new(200, "Okay", undef, $cont);
        $cc->send_response($res);
    }
}

our $httpd_port = 10080;
our $httpd_addr = "127.0.0.1";
my %have_files;
#our $wsd_url = "ws://localhost:12345/";
my $wsd_url = "ws://10.11.12.13:34567/";
our $httpd_url = "http://" . $httpd_addr .":". $httpd_port ."/";

sub sweep_HTMLcontfiles {
    my($dir) = @_;
    
    if($debug_httpd) {
        print "sweep_HTMLcontfiles: dir |$dir|\n";
    }
    opendir(DIR, $dir) || return ;
    my @fs = grep {/\.html$/} grep {!/^\./}  readdir(DIR);
#    my @fs = grep {/\.html$/} readdir(DIR);
    closedir(DIR);

    if($dir eq '.') {
        foreach my $x (@fs) {
            $have_files{"/".$x} = $x;
        }       
    }
    else {
        foreach my $x (@fs) {
            $have_files{"/".$dir."/".$x} = $dir."/".$x;
        }       
    }
    if($debug_httpd) {
        print "got $#fs file(s)\n";
    }

    if(0) {
        foreach my $x (sort keys %have_files) {
            print "$x $have_files{$x}\n";
        }       
    }
}

sub sweep_contfiles {
    my($dir) = @_;
    
    if($debug_httpd) {
        print "sweep_contfile: dir |$dir|\n";
    }
    opendir(DIR, $dir) || return ;
    my @fs = grep {!/^\./}  readdir(DIR);
#    my @fs = readdir(DIR);
    closedir(DIR);

    if($debug_httpd) {
        print "got $#fs file(s)\n";
    }

    if($dir eq '.') {
        foreach my $x (@fs) {
            $have_files{"/".$x} = $x;
        }       
    }
    else {
        foreach my $x (@fs) {
            $have_files{"/".$dir."/".$x} = $dir."/".$x;
        }       
    }

    if(0) {
        foreach my $x (sort keys %have_files) {
            print "$x -> $have_files{$x}\n";
        }       
    }
}

sub sweep_contfilesR {
    my($basedir) = @_;
    my @target;

    if($debug_httpd) {
        print "sweep_contfile: basedir |$basedir|\n";
    }

    push(@target, $basedir);

    while(@target) {
        my $dir = pop(@target);
        if($debug_httpd) {
            print "  dir |$dir|\n";
        }

        my $path;

        opendir(my $dh, $dir) || return ;

        my $fn;
        while(defined($fn = readdir($dh))) {
            next if $fn eq '.';
            next if $fn eq '..';
            $path = "$dir/$fn";

            if(-d $path) {
                push(@target, $path);
            }
            else {
            if($debug_httpd) {
                print "  file |$fn| $path\n";
            }
                my $spath;
                $spath = substr($path, length($basedir)+1);
                $have_files{"/".$spath} = $path;
            }
        }
    }

    if(0) {
        foreach my $x (sort keys %have_files) {
            print "$x -> $have_files{$x}\n";
        }       
    }
}

sub add_contfile {
    my($fn) = @_;
    if( -f $fn ) {
        $have_files{"/". $fn } = $fn;
        if($debug_httpd) {
            print "add_contfile: added $fn\n";
        }
    }
    else {
        print "add_contfile: ERROR not found $fn\n";
    }
}

sub set_maincontfile {
    my($fn) = @_;
    if( -f $fn ) {
        $have_files{"/" } = $fn;
        if($debug_httpd) {
            print "set_maincontfile: set $fn as /\n";
        }
    }
    else {
        print "set_maincontfile: ERROR not found $fn\n";
    }
}


sub dmy_start {
    &sweep_contfiles(".");
    &add_contfile("vis.js");
    &set_maincontfile("vis.html");
}


#openlog("cyrisvismon", "nowait,pid", LOG_USER);
openlog("cyrisvismon", "nowait,pid", LOG_LOCAL0);

my %callbackdict : shared;
my $digestpolicy : shared;
my %digestdict   : shared;

$digestpolicy = 'none';

sub digest_setpolicy {
    my($xval) = @_;
    $digestpolicy = $xval;
}

sub digest_cleardict {
    %digestdict = ();
}

sub digest_addpath {
    my($xval) = @_;
    $digestdict{$xval} = 1;
}

sub isrequireddigest {
    my($xpass) = @_;
    if($digestpolicy eq 'none') {
        return 0;
    }
    elsif($digestpolicy eq 'all') {
        return 1;
    }
    else {
        if(defined $digestdict{$xpass}) {
            return 1;
        }
        else {
            return 0;
        }
    }
}

sub mkdigestpromptheader {
    my $ah;
    my $nonce;
    my $realm;
    my $qop;

    $ah    = HTTP::Headers->new;
    $realm = "Digest Auth";
    $nonce = "aHZlqj8CBQA=e444ef7072d5cc9e9682e0aeea334f8454d92f9c";
    $qop   = "auth";
    
    $ah->header('WWW-Authenticate' =>
        'Digest realm="'.$realm.'", nonce="'.$nonce.'", '.
        'algorithm=MD5, qop="'.$qop.'"');
    return $ah;
}

sub hasdigestauth {
    my ($rq_ref) = @_;
    my $ahv = '';
    my $cq;
    my $xmethod;
    if($debug_httpd) {
        print "************ hasdigestauth\n";
        print "rq_ref $rq_ref\n";
    }
    while ( my ($k,$v) = each %$rq_ref) {
        if($debug_httpd) {
            print "|$k| |$v|\n";
        }

        if($k eq "_method") {
            $xmethod = $v;
        }
        if($k eq "_headers") {
            while ( my ($n,$a) = each %$v) {
                if($debug_httpd) {
                    print "  |$n| |$a|\n";
                }
                if($n eq 'WWW-Authenticate:' || $n eq 'authorization') {
                    $ahv = $a;
                }
            }
        }
    }

    if($debug_httpd) {
        print "ahv |$ahv|\n";
    }
    return $ahv;
  if(0) {
    if($ahv eq '') {
        return 0;
    }
    else {
        return 1;
    }
  }
}

our %Nuptbl : shared;
#%Nuptbl = ("abc"=>"ajapa","xyz"=>"xeon");


sub uptbl_numusers {
    my $n;
    my $v;
    my $i;
    $i = 0;
    while(($n, $v) = each %Nuptbl) {
        $i++;
    }
    return $i;
}

sub uptbl_list {
    my $n;
    my $v;
    my $i;
    $i = 0;
    print "======\n";
    while(($n, $v) = each %Nuptbl) {
        print "    user |$n| passwd |$v| ******\n";
        $i++;
    }
    if($i==0) {
        print "### NOUSER ? ###\n";
    }
    print "======\n";
}

sub uptbl_setpair {
    my($k, $v) = @_;
    $Nuptbl{$k} = $v;
}

sub uptbl_loadfile {
    my ($fn) = @_;
    my @f;
    open(F, "<$fn");
    while(<F>) {
        if(/^\s*#/) {
            next;
        }
        @f = split;
        $Nuptbl{$f[0]} = $f[1];
    }
    close(F);

    if($debug_httpd) {
        &uptbl_list;
    }
}


sub ckdigestvalue {
    my($full, $xmethod) = @_;
    my %pairs;
    my $k;
    my $v;
    my $rk;

    $rk = -1;

    if($debug_httpd_auth) {
        print "full |$full|\n";
    }
    foreach my $x (split(/,/, $full)) {
#       if($x =~ /([A-Za-z0-9_]+)=(\"?[^"]*\"?)/) 
        if($x =~ /([A-Za-z0-9_]+)=\"?([^"]*)\"?/) 
        {
            $k = $1;
            $v = $2;
            $pairs{$k} = $v;
        }
    }

    if($debug_httpd_auth) {
        foreach $k (keys %pairs) {
            printf "  %-16s %s\n", $k, $pairs{$k};
        }
    }
  {
        my $username;
        my $passwd;
        my $a1;
        my $h_a1;
        my $a2;
        my $h_a2;
        my $realm;
        my $method;
        my $uri;
        my $nonce;
        my $cnonce;
        my $qop;
        my $response;
        my $h_response;
        my $nc;

 if(0) {
        print "before:\n";
        &uptbl_list;
        $Nuptbl{"dmy"} = "dmyval";
        print "middle:\n";
        &uptbl_list;
 }

        $username = $pairs{"username"};
        if($username =~ /^"(.*)"$/) {
            $username = $1;
        }
if($debug_httpd_auth) {
print "- - - - - |$username| - - - - -\n";
}
        if(!defined $Nuptbl{$username}) {
            print "unknown user '$username'\n";
            if($debug_httpd_auth) {
                &uptbl_list;
            }
            goto NOUSER;
        }
        $passwd = $Nuptbl{$username};

if($debug_httpd_auth) {
print "passwd $passwd\n";
}
        
        $realm = $pairs{"realm"};
        $method= $pairs{"method"};
        if($method eq '') {
            $method = $xmethod;
        }
        $uri   = $pairs{"uri"};
if($debug_httpd_auth) {
print "pass 5\n";
}
        $nonce = $pairs{"nonce"};
        $cnonce= $pairs{"cnonce"};
        $qop   = $pairs{"qop"};
        $nc    = $pairs{"nc"};

if($debug_httpd_auth) {
print "pass 10\n";
}

        $a1    = "$username:$realm:$passwd";
        $h_a1  = md5_hex($a1);
        $a2    = "$method:$uri";
        $h_a2  = md5_hex($a2);

if($debug_httpd_auth) {
print "pass 20\n";
}

if($debug_httpd_auth) {
print  "a1         $a1\n";
print  "h_a1       $h_a1\n";
print  "a2         $a2\n";
print  "h_a2       $h_a2\n";
}
        $response = "$h_a1:$nonce:$nc:$cnonce:$qop:$h_a2";
        $h_response = md5_hex($response);
if($debug_httpd_auth) {
print "pass 30\n";
}
        
if($debug_httpd_auth) {
print  "response   $response\n";
print  "h_response $h_response\n";
print "pass 40\n";
}

        if($h_response eq $pairs{"response"}) {
            if($debug_httpd_auth) {
            print " *** SUCCESS ***\n";
            }
            $rk = 0;
        }
        else {
            if($debug_httpd_auth) {
            print " *** FAIL ***\n";
            }
            $rk = 1;
        }
  }

NOUSER:

    return $rk;
}

sub httpd_mainbody {
    my $dm = HTTP::Daemon->new(
                ReuseAddr => 1,
                LocalAddr => $httpd_addr, 
                LocalPort => $httpd_port) || die;
    my $h;
    if($debug_httpd) {
        print "HTTP service URL: ", $dm->url, "\n";
    }

    syslog(LOG_INFO, "HTTPD UP");

    while (my $cc = $dm->accept) {
        if($debug_httpd) {
            print "got new HTTP connection\n";
#           print "cc $cc\n";
        }
        $fc++;
        $convdict{"fid"} = $fc;
        while (my $rq = $cc->get_request) {
            $cc->force_last_request;

            $h = &hash($rq->url->path);
if($debug_httpd) {
    print "request |".$rq->url->path."| <$h>\n";
}

###
### AUTH BLOCK
###
            my $authok;
            my $authrc;

            $authok = -1;
            $authrc = 0;
            if(&isrequireddigest($rq->url->path)) {
                my $auh;
                if($debug_httpd) {
                    print "digest REQUIRED\n";
                }
                $auh = &hasdigestauth($rq);
                if($auh ne '') {
                    my $ik;
                    $ik = &ckdigestvalue($auh, $rq->method);
                    if($ik == 0) {
                        $authok = 0; $authrc = 200;
                    }
                    else {
                        $authok = 1; $authrc = 401;
                    }
                }
                else {  
                    $authok = 1;     $authrc = 401;
                }
            }
            else {
                $authok = 0;
                if($debug_httpd) {
                    print "digest NOT required\n";
                }
            }

            if($authok!=0) {
                my $cont;
                my $ah;

                $cont = "<h1>AuthError</h1>\n";
                $ah = &mkdigestpromptheader;
                my $res = HTTP::Response->new(401, "Unauthorized", $ah, $cont);
                $cc->send_response($res);

                goto NEXT;
            }

###
### CALLBACK BLOCK
###
            if(defined $callbackdict{$rq->url->path}) {
                my $a;
                my $f = $callbackdict{$rq->url->path};
if($debug_httpd) {
    print "request |".$rq->url->path."| callback registed |$f|\n";
}
                $a = $rq->url->path;
                if($debug_httpd) {
                    print "cc $cc\n";
                    print "rq $rq\n";
                }
                eval "&$f(\$cc,\$rq)";          # maybe

                goto NEXT;
            }
            else {
if($debug_httpd) {
    print "request |".$rq->url->path."| callback NOT-registed\n";
}
            }

            if ($rq->method eq 'GET') {
                if(defined $have_files{$rq->url->path}) {
#   &send_file_wconv($cc, $have_files{$rq->url->path}, $dm->url, $wsurl);
    &send_file_wconv($cc, $have_files{$rq->url->path}, $httpd_url, $wsd_url);
                        syslog(LOG_INFO, "HTTPD SEND ".$rq->url->path." OK");
                        print("HTTPD SEND ".$rq->url->path." OK"."\n");
                }
                else {
                    if($cc->antique_client) {
                    }
                    else {
                        $cc->send_status_line(403);
                        syslog(LOG_INFO, "HTTPD SEND ".$rq->url->path." NOT-FOUND");
                        print("HTTPD SEND ".$rq->url->path." NOT-FOUND"."\n");
                    }
                }
            }
            else {
                $cc->send_error(RC_FORBIDDEN)
            }
        }
NEXT:
        $cc->close;
        undef($cc);
    }
}

sub httpd_debug {
    $debug_httpd = 1;
}
sub httpd_nodebug {
    $debug_httpd = 0;
}
sub httpd_authdebug {
    $debug_httpd_auth = 1;
}
sub httpd_noauthdebug {
    $debug_httpd_auth = 0;
}
sub set_httpd_url {
    my($x) = @_;
    $httpd_url = $x;
}
sub set_wsd_url {
    my($x) = @_;
    $wsd_url = $x;
}


sub hash {
    my ($instr) = @_;
    my @p = split(//, $instr);
    my $s;
    my $u;
    my $outstr;
    $s = 1137;
    foreach my $x (@p) {
        $u = unpack('c1', $x);
        $s = $s << 3;
        $s += $u;
    }
    $s = $s & 0xffff;
    $outstr = sprintf("%04x", $s);
    return $outstr;
}

sub list_callback {
    my $kc;
    my $h;
    $kc=0;
    foreach my $k (keys %callbackdict) {
        $h = &hash($k);
        printf "%3d %4s %-16s %s\n",
            $kc, $h, "|".$k."|", "|".$callbackdict{$k}."|";
        $kc++;
    }
}

sub set_callback {
    my($url, $namecallback) = @_;
    my $h;
    $h = &hash($url);
    if($debug_httpd) {
        print "set_callback |$url| <$h> |$namecallback|\n";
    }

    if($debug_httpd) {
        print "before:\n";
        &list_callback;
    }

    $callbackdict{$url} = $namecallback;

    if($debug_httpd) {
        print "after:\n";
        &list_callback;
    }
}

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    $httpd_port $httpd_addr $httpd_url
    set_wsd_url
    httpd_mainbody
    sweep_HTMLcontfiles sweep_contfiles sweep_contfilesR
    add_contfile set_maincontfile
    httpd_debug httpd_nodebug
    httpd_authdebug httpd_noauthdebug
    set_callback list_callback
    digest_setpolicy digest_addpath digest_cleardict
    uptbl_setpair uptbl_loadfile uptbl_list uptbl_numusers
    );

1;

