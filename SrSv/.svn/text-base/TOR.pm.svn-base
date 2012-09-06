#!/usr/bin/perl

#       This file is part of SurrealServices.
#
#       SurrealServices is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       SurrealServices is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with SurrealServices; if not, write to the Free Software
#       Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=pod
	Parses the TOR router list for exit-nodes, and optionally
	for exit-nodes that can connect to our services.

	Interface still in progress.
=cut

package SrSv::TOR;
use strict;

use Exporter 'import';
BEGIN { our @EXPORT = qw( getTorRouters ); }

sub openURI($) {
	my ($URI) = @_;
	my $fh;
	if($URI =~ s/^file:\/\///i) {
		open($fh, '<', $URI) or die;
	} else {
	# assume HTTP/FTP URI
		open($fh, '-|', ('wget -q -O - ' . $URI)) or die;
	}
	return $fh;
}

sub parseTorRouterList($) {
	my ($fh) = @_;
	my (%currentRouter, @routerList);
	while (my $l = <$fh>) {
		#print "$l";
		chomp $l;
		if($l =~ /^r (\S)+ (?:[a-zA-Z0-9+\/]+) (?:[a-zA-Z0-9+\/]+) (?:\d{4}-\d{2}-\d{2} \d\d:\d\d:\d\d) (\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}) (\d+) (\d+)/) {
		#r atari i2i65Qm8DXfRpHVk6N0tcT0fxvs djULF2FbASFyIzuSpH1Zit9cYFc 2007-10-07 00:19:17 85.31.187.200 9001 9030
			#print "( NAME => $1, IP => \"$2.$3.$4.$5\", IN_PORT => $6, DIR_PORT => $7 )\n";
			%currentRouter = ( NAME => $1, IP => "$2.$3.$4.$5", IN_PORT => $6, DIR_PORT => $7 );
		} 
		elsif($l =~ /^s (.*)/) {
		#s Exit Fast Guard Stable Running V2Dir Valid
			my $tokens = $1;
			# uncomment the conditional if you trust the router status flags
#			if($tokens =~ /Exit/) {
				push @routerList, $currentRouter{IP};
#			}
		}
		elsif($l =~ /router (\S+) (\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}) (\d+) (\d+) (\d+)/) {
			push @routerList, processTorRouter(%currentRouter) if scalar(%currentRouter);
			%currentRouter = ( NAME => $1, IP => "$2.$3.$4.$5", IN_PORT => $6, DIR_PORT => $8 );
		} elsif($l =~ /reject (\S+):(\S+)/) {
			#print STDERR "$currentRouter{IP} reject $1:$2\n";
			push @{$currentRouter{REJECT}}, "$1:$2";
		} elsif($l =~ /accept (\S+):(\S+)/) {
			#print STDERR "$currentRouter{IP} accept $1:$2\n";
			push @{$currentRouter{ACCEPT}}, "$1:$2";
		}
	}
	close $fh;
	return @routerList;
}

sub processTorRouter(%) {
# only used for v1, and possibly v3
	my (%routerData) = @_;
	my @rejectList = ( $routerData{REJECT} and scalar(@{$routerData{REJECT}}) ? @{$routerData{REJECT}} : () );
	my @acceptList = ( $routerData{ACCEPT} and scalar(@{$routerData{ACCEPT}}) ? @{$routerData{ACCEPT}} : () );
	return () if $routerData{IP} =~ /^(127|10|192\.168)\./;
	if ( (scalar(@rejectList) == 1) and ($rejectList[0] eq '*:*') ) {
		#print STDERR "$routerData{IP} is not an exit node.\n";
		return ();
	} else {
		#print STDERR "$routerData{IP} is an exit node.\n";
		return ($routerData{IP});
	}
}

sub getTorRouters($) {
	my ($URI) = @_;
	return parseTorRouterList(openURI($URI));
}

1;
