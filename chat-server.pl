#!/usr/bin/perl
# chat-server.pl: character mode chat server
use strict;
use warnings;
BEGIN { $ENV{PATH} = "/usr/bin:/bin" }
use Socket;
use Carp;
my $EOL = "\015\012";

sub logmsg { print(scalar localtime(), ": $0 $$: @_\n") }
sub broadcast { logmsg }

my $port  = shift || 2345;
die "invalid port" unless $port =~ /^ \d+ $/x;

my $proto = getprotobyname("tcp");

socket(my $server, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";
setsockopt($server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))
                                              || die "setsockopt: $!";
bind($server, sockaddr_in($port, INADDR_ANY)) || die "bind: $!";
listen($server, SOMAXCONN)                    || die "listen: $!";

logmsg "$0 started on port $port";

my @client_fh = ();
my @client_in = ();
my @client_out = ();
my @client_name = ();

my $running = 1;
while($running) {
	my $rin = my $win = my $ein = '';
	vec($rin, fileno($server), 1)=1;
	for(my $i=0; $i<scalar(@client_fh); $i++) {
		vec($rin, fileno($client_fh[$i]), 1)=1;
		vec($win, fileno($client_fh[$i]), 1)=1 if scalar(@{$client_out[$i]}) > 0;
	}
	my ($nfound, $timeleft) = select(my $rout = $rin, my $wout = $win, my $eout = $ein, 1.0);
	next unless $nfound > 0;

	if(vec($rout, fileno($server), 1) != 0) {
		my $paddr = accept(my $client, $server);
    	my($port, $iaddr) = sockaddr_in($paddr);
    	my $name = gethostbyaddr($iaddr, AF_INET);
    	logmsg "connection from $name [", inet_ntoa($iaddr), "] at port $port";
		$client->autoflush(1);

		push @client_fh, $client;
		my @out_buf = ('N', 'a', 'm', 'e', '?', ' ');
		push @client_out, \@out_buf;
		my @in_buf = ();
		push @client_in, \@in_buf;
		my @name_buf = ();
		push @client_name, \@name_buf;
	}

	for(my $i=0; $i<scalar(@client_fh); $i++) {
		my $fh = $client_fh[$i];

		# client input
		if(vec($rout, fileno($fh), 1) != 0) {
			my $read = sysread $fh, my $buffer, 1;
			if(!defined($read) or $read==0) {
				# client terminated
				logmsg "client terminated";
				splice @client_fh, $i, 1;
				splice @client_in, $i, 1;
				splice @client_out, $i, 1;
				close $fh;
				last;
			}
			push @{$client_in[$i]}, $buffer;
			if(unpack("W", $buffer) == 10) {
				my $cname = join("", @{$client_in[$i]});
				chomp $cname;
				logmsg "<< ", $cname;

				if(scalar(@{$client_name[$i]}) == 0) {
					# set name
					push @{$client_name[$i]}, @{$client_in[$i]};
					pop @{$client_name[$i]}; # chomp
					push @{$client_name[$i]}, (':', ' ');
				}
				else {
					# broadcast message
					for(my $j=0; $j<scalar(@client_fh); $j++) {
						if($i != $j) {
							push @{$client_out[$j]}, @{$client_name[$i]};
							push @{$client_out[$j]}, @{$client_in[$i]};
						}
					}
				}
				my @buf = ();
				$client_in[$i] = \@buf;
			}
		}

		# client output
		if(vec($wout, fileno($fh), 1) != 0 and scalar(@{$client_out[$i]})>0) {
			syswrite $fh, shift(@{$client_out[$i]});
		}
	}
}
