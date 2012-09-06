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

package SrSv::User;

=head1 NAME

SrSv::User - Track users

=head1 SYNOPSIS

 use SrSv::User qw(get_user_id get_user_nick get_user_agent is_online chk_online get_user_flags set_user_flag chk_user_flag);

=cut

use strict;

use Exporter 'import';
BEGIN {
	my %constants = (
		UF_FINISHED => 1,
		UF_ONLINE => 2, # not used yet
	);

	our @EXPORT_OK = (qw(get_user_id get_user_nick get_user_agent is_online chk_online 
		$get_user_id $get_user_nick
		get_user_ip
		get_user_flags set_user_flag chk_user_flag set_user_flag_all 
		get_host get_vhost get_cloakhost get_user_info
		),
		keys(%constants));
	
	our %EXPORT_TAGS = (flags => [keys(%constants)]);

	require constant; import constant (\%constants);
}

use SrSv::MySQL::Stub {
	 __getIPV4 => ['SCALAR', "SELECT INET_NTOA(ip) FROM user WHERE id=?"],
};
	
	

use SrSv::Process::Init;
use SrSv::MySQL '$dbh';
use SrSv::NickControl::Enforcer qw(%enforcers);
use SrSv::IRCd::State qw(synced);
use SrSv::Agent qw(is_agent);
use SrSv::User::Notice;

use SrSv::Log;

our (
	$get_user_id, $get_user_nick, $get_nickchg, $is_online,

	$get_user_flags, $set_user_flag, $unset_user_flag, $set_user_flag_all,

	$get_host, $get_vhost, $get_cloakhost, $get_ip, $get_user_info,
);

proc_init {
	$get_user_id = $dbh->prepare("SELECT id FROM user WHERE nick=?");
	$get_user_nick = $dbh->prepare("SELECT nick FROM user WHERE id=?");
	$get_nickchg = $dbh->prepare("SELECT nickchg.nickid, user.nick FROM nickchg, user WHERE user.id=nickchg.nickid AND nickchg.nick=?");
	$is_online = $dbh->prepare("SELECT 1 FROM user WHERE nick=? AND online=1");

	$get_user_flags = $dbh->prepare("SELECT flags FROM user WHERE id=?");
	$set_user_flag = $dbh->prepare("UPDATE user SET flags=(flags | (?)) WHERE id=?");
	$unset_user_flag = $dbh->prepare("UPDATE user SET flags=(flags & ~(?)) WHERE id=?");
	$set_user_flag_all = $dbh->prepare("UPDATE user SET flags=flags | ?");

	$get_host = $dbh->prepare("SELECT ident, host FROM user WHERE id=?");
	$get_vhost = $dbh->prepare("SELECT ident, vhost FROM user WHERE id=?");
	$get_cloakhost = $dbh->prepare("SELECT 1, cloakhost FROM user WHERE id=?");
	$get_user_info  = $dbh->prepare("SELECT ident, host, vhost, gecos, server FROM user WHERE id=?");
};

sub get_user_id($) {
	my ($user) = @_;
	my ($id, $n);

	return undef if(is_agent($user->{NICK}) and not $enforcers{lc $user->{NICK}});

	unless(ref($user) eq 'HASH') {
		die("invalid get_user_nick call");
	}

	if(exists($user->{ID})) { return $user->{ID}; }

	my $nick = $user->{NICK};

	# a cheat for isServer()
	if($user->{NICK} =~ /\./) {
		return $user->{ID} = undef;
	}

	if($nick eq '') {
		die("get_user_id called on empty string");
	}

	my $nick2;
	while($n < 10 and !defined($id)) {
		$n++;
		$get_user_id->execute($nick);
		($id) = $get_user_id->fetchrow_array;
		unless($id) {
			$get_nickchg->execute($nick);
			($id, $nick2) = $get_nickchg->fetchrow_array;
		}
	}

	#unless($id) { log::wlog(__PACKAGE__, log::DEBUG(), "get_user_id($nick) failed."); }

	if(defined($nick2) and lc $nick2 ne lc $user->{NICK}) {
		$user->{OLDNICK} = $user->{NICK};
		$user->{NICK} = $nick2;
	}

	return $user->{ID} = $id;
}

sub get_user_nick($) {
	my ($user) = @_;

	unless(ref($user) eq 'HASH') {
		die("invalid get_user_nick call");
	}

	if(exists($user->{NICK}) and is_online($user->{NICK})) { return $user->{NICK} }

	# Possible bug? This next bit only works to chase the nick-change
	# if the caller already did a get_user_id to find out
	# if the user exists in the user table, and thus get $user->{ID}
	# I don't know if calling get_user_id here is safe or not.
	my $nick;
	if($user->{ID}) {
		$get_user_nick->execute($user->{ID});
		($nick) = $get_user_nick->fetchrow_array;
	}

	# avoid returning an undef/NULL here. That's only legal for get_user_id
	# If the user does not exist, we must avoid modifying the input
	# so that it may be used for the error paths.
	return (defined $nick ? $user->{NICK} = $nick : $user->{NICK});
}

sub get_user_agent($) {
	my ($user) = @_;

=cut
	eval { $user->{AGENT} };
	if($@) {
		die("invalid get_user_agent call");
	}
=cut
	die "invalid get_user_agent call" unless ref($user) eq 'HASH';

	if(exists($user->{AGENT})) {
		return $user->{AGENT}
	}
	else {
		return undef;
	}
}

sub is_online($) {
	my ($user) = @_;
	my $nick;

	if(ref($user)) {
		if(exists($user->{ONLINE})) { return $user->{ONLINE}; }
		$nick = get_user_nick($user);
	} else {
		$nick = $user;
	}

	$is_online->execute($nick);
	my ($status) = $is_online->fetchrow_array;
	$is_online->finish();
	if(ref($user)) {
		$user->{ONLINE} = ($status ? 1 : 0);
	}

	return $status;
}

sub chk_online($$) {
	my ($user, $target) = @_;

	unless(is_online($target)) {
		if(ref($target)) {
			$target = get_user_nick($target);
		}

		notice($user, "\002$target\002: No such user.");
		return 0;
	}

	return 1;
}

sub set_user_flag($$;$) {
	my ($user, $flag, $sign) = @_;
	my $uid = get_user_id($user);
	$sign = 1 unless defined($sign);

	if($sign) {
		$user->{FLAGS} = ( ( defined $user->{FLAGS} ? $user->{FLAGS} : 0 ) | $flag );
		$set_user_flag->execute($flag, $uid);
	} else {
		$user->{FLAGS} = ( ( defined $user->{FLAGS} ? $user->{FLAGS} : 0 ) & ~($flag) );
		$unset_user_flag->execute($flag, $uid);
	}
}

sub chk_user_flag($$;$) {
	my ($user, $flag, $sign) = @_;
	my $flags = get_user_flags($user);
	$sign = 1 unless defined($sign);

	return ($sign ? ($flags & $flag) : !($flags & $flag));
}

sub get_user_flags($) {
	my ($user) = @_;
	my $uid = get_user_id($user);

	my $flags;
	unless (exists($user->{FLAGS})) {
		$get_user_flags->execute($uid);
		($flags) = $get_user_flags->fetchrow_array;
		$get_user_flags->finish();
	} else {
		$flags = $user->{FLAGS};
	}

	return $user->{FLAGS} = $flags;
}

sub set_user_flag_all($) {
	my ($flags) = @_;

	$set_user_flag_all->execute($flags);
	$set_user_flag_all->finish();
}

sub get_host($) {
	my ($user) = @_;

	my $id;
	if(ref($user)) {
		$id = get_user_id($user);
	} else {
		$id = get_user_id({ NICK => $user });
	}
	return undef unless $id;

	$get_host->execute($id);
	my ($ident, $host) = $get_host->fetchrow_array;

	return ($ident, $host);
}

sub get_cloakhost($) {
	my ($user) = @_;

	my $id;
	if(ref($user)) {
		$id = get_user_id($user);
	} else {
		$id = get_user_id({ NICK => $user });
	}
	return undef unless $id;

	$get_cloakhost->execute($id);
	my ($valid, $cloakhost) = $get_cloakhost->fetchrow_array;
	$get_cloakhost->finish;

	# Beware, $cloakhost may be NULL while the user entry exists
	# if $cloakhost == undef, check $valid before assuming no such user.
	return ($valid, $cloakhost);
}

sub get_vhost($) {
	my ($user) = @_;

	my $id;
	if(ref($user)) {
		$id = get_user_id($user);
	} else {
		$id = get_user_id({ NICK => $user });
	}
	return undef unless $id;

	$get_vhost->execute($id);
	my ($ident, $vhost) = $get_vhost->fetchrow_array;

	return ($ident, $vhost);
}

sub get_user_info($) {
	my ($user) = @_;

	my $uid = get_user_id($user);
	return undef() unless $uid;

	$get_user_info->execute($uid);
	my ($ident, $host, $vhost, $gecos, $server) = $get_user_info->fetchrow_array();
	$get_user_info->finish;

	return ($ident, $host, $vhost, $gecos, $server);
}

sub get_user_ipv4($) {
	my ($user) = @_;

	my $id;
	if(ref($user)) {
		if(exists $user->{IP}) {
			return $user->{IP};
		}
		$id = get_user_id($user);
	} else {
		$id = get_user_id({ NICK => $user });
	}
	return undef unless $id;

	my $ip = getIPV4($id);
	if(ref($user)) {
		return $user->{IP} = $ip;
	} else {
		return $ip;
	}
}

sub get_user_ip($) {
	return get_user_ipv4(@_);
}

1;
