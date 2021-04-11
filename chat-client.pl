#!/usr/bin/perl
# chat-client.pl: character mode telnet client
use strict;
use warnings;
use Socket;

my $remote  = shift || "localhost";
my $port    = shift || 2345;  # random port
if ($port =~ /\D/) { $port = getservbyname($port, "tcp") }
die "No port" unless $port;
my $iaddr   = inet_aton($remote)       || die "no host: $remote";
my $paddr   = sockaddr_in($port, $iaddr);

my $proto   = getprotobyname("tcp");
socket(my $sock, PF_INET, SOCK_STREAM, $proto)  || die "socket: $!";
connect($sock, $paddr)              || die "connect: $!";

#STDOUT->autoflush(1);
binmode STDIN;
binmode STDOUT;
binmode $sock;

my @user_buffer = ();
my @server_buffer = ();

my $cursor = "?";

my $running = 1;
while($running) {
	my $rin = my $win = my $ein = '';
	vec($rin, fileno(STDIN), 1)=1;
	vec($rin, fileno($sock), 1)=1;
	vec($win, fileno(STDOUT),1)=1 if scalar(@server_buffer) > 0;
	vec($win, fileno($sock), 1)=1 if scalar(@user_buffer) > 0;
	my ($nfound, $timeleft) = select(my $rout = $rin, my $wout = $win, my $eout = '', 1.0);
	#print "nfound = $nfound\n";
	if($nfound == 0) {
		syswrite STDOUT, "$cursor\b";
		$cursor = $cursor eq "?" ? " " : "?";
		next;
	}

	# read next char of user input
	if(vec($rout, fileno(STDIN), 1) != 0) {
		my $read = sysread STDIN, my $buffer, 1;
		if($read == 0) { $running = 0; next; }
		push @user_buffer, $buffer;
	}

	# read next char of server input
	if(vec($rout, fileno($sock), 1) != 0) {
		sysread $sock, my $buffer, 1;
		push @server_buffer, $buffer;
	}

	# write server buffer
	if(vec($wout, fileno(STDOUT), 1) != 0 && scalar(@server_buffer) > 0) {
		syswrite STDOUT, shift(@server_buffer);
	}

	# write user buffer
	if(vec($wout, fileno($sock), 1) != 0 && scalar(@user_buffer) > 0) {
		syswrite $sock, shift(@user_buffer);
	}
}
close ($sock)                        || die "close: $!";
exit(0);
