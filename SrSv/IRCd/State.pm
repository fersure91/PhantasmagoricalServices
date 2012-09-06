#	This file is part of SurrealServices.
#
#	SurrealServices is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#
#	SurrealServices is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with SurrealServices; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package SrSv::IRCd::State;


use strict;

use Exporter 'import';
our @EXPORT_OK = qw($ircline $ircline_real $remoteserv $ircd_ready synced initial_synced create_server get_server_children set_server_state set_server_juped get_server_state get_online_servers %IRCd_capabilities);

# FIXME - synced() is called very often and should be cached locally
use SrSv::Process::InParent qw(calc_synced create_server get_server_children set_server_state set_server_juped get_server_state get_online_servers);

use SrSv::Conf 'main';

use SrSv::Debug;

use SrSv::Shared qw(%IRCd_capabilities);

our $ircline = 0;
our $ircline_real = 0;
our $remoteserv;
our $ircd_ready;

our %servers;
our %juped_servers;
our $synced;
our $initial_synced;

sub synced {
	return $synced;
}

sub initial_synced {
	return $initial_synced;
}

sub calc_synced {
	#return ($sync and $sync < $ircd::ircline);

	SYNCED: {
		foreach my $s (keys(%servers)) {
			my $state = get_server_state($s);

			print "Server: $s  State: $state\n" if DEBUG();

			if(!$state) {
				$synced = 0;
				last SYNCED;
			}
		}

		$synced = 1;
	}

	{
		my $state = get_server_state($remoteserv);
		if(!$state) {
			$initial_synced = 0;
		} else {
			$initial_synced = 1;
		}
	}
}

sub create_server($$) {
	my ($child, $parent) = @_;

	$servers{$child} = {
		PARENT => $parent,
		CHILDREN => [],
		SYNCED => 0,
	};

	push @{$servers{$parent}{CHILDREN}}, $child if $parent;

	calc_synced();
}

sub get_server_children($) {
	my ($s) = @_;
	return ($s, map get_server_children($_), @{$servers{$s}{CHILDREN}});
}

sub set_server_state {
	my ($server, $state) = @_;

	if(defined($state)) {
		return if $juped_servers{$server};

		$servers{$server}{SYNCED} = $state;
	} else {
		delete $juped_servers{$server};

		if(my $parent = $servers{$server}{PARENT}) {
			$servers{$parent}{CHILDREN} = [
				grep {$_ ne $server} @{$servers{$parent}{CHILDREN}}
			];
		}

		foreach (get_server_children($server)) {
			delete $servers{$_};
		}
	}

	calc_synced();
}

sub set_server_juped($) {
	my ($server) = @_;

	set_server_state($server, undef);
	$juped_servers{$server} = 1;
}

sub get_server_state {
	my ($server) = @_;

	my $badserver = $main_conf{'unsyncserver'};
	return 1 if($badserver and lc $server eq lc $badserver); # I HATE NEOSTATS

	return $servers{$server}{SYNCED};
}

sub get_online_servers {
	my @online_servers;
	foreach my $server (keys(%servers)) {
		push @online_servers, $server if $servers{$server}{SYNCED};
	}
	return @online_servers;
}

1;
