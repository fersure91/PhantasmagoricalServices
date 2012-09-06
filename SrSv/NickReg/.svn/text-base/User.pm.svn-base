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

package SrSv::NickReg::User;

=head1 NAME

SrSv::NickReg::User - Determine which users are identified to which nicks

=cut

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw(is_identified chk_identified get_id_nicks get_nick_user_nicks get_nick_users) }

use SrSv::Process::Init;
use SrSv::MySQL '$dbh';
use SrSv::User qw(:flags get_user_nick get_user_id);
use SrSv::User::Notice;
use SrSv::NickReg::Flags;
use SrSv::Errors;

our ($is_identified, $get_id_nicks, $get_nick_users);

proc_init {
	$is_identified = $dbh->prepare("SELECT 1 FROM user, nickid, nickalias WHERE user.id=nickid.id AND user.nick=? AND nickid.nrid=nickalias.nrid AND nickalias.alias=?");
	$get_id_nicks = $dbh->prepare("SELECT nickreg.nick FROM nickid, nickreg WHERE nickid.nrid=nickreg.id AND nickid.id=?");
	$get_nick_users = $dbh->prepare("SELECT user.nick, user.id FROM user, nickid, nickalias WHERE user.id=nickid.id AND nickid.nrid=nickalias.nrid AND nickalias.alias=? AND user.online=1");
};

sub is_identified($$) {
	my ($user, $rnick) = @_;
	my $nick = get_user_nick($user);
	
	$is_identified->execute($nick, $rnick);
	return scalar $is_identified->fetchrow_array;
}

sub chk_identified($;$) {
	my ($user, $nick) = @_;

	$nick = get_user_nick($user) unless $nick;
	
	nickserv::chk_registered($user, $nick) or return 0;

	unless(is_identified($user, $nick)) {
		notice($user, $err_deny);
		return 0;
	}
	
	return 1;
}

sub get_id_nicks($) {
	my ($user) = @_;
	my $id = get_user_id($user);
	my @nicks;

	$get_id_nicks->execute($id);
	my $ref = $get_id_nicks->fetchall_arrayref;

	return map $_->[0], @$ref;
}

sub get_nick_user_nicks($) {
	my ($nick) = @_;

	$get_nick_users->execute($nick);
	my $ref = $get_nick_users->fetchall_arrayref;

	return map $_->[0], @$ref;
}

sub get_nick_users($) {
	my ($nick) = @_;

	$get_nick_users->execute($nick);
	my $ref = $get_nick_users->fetchall_arrayref;
	
	return map +{NICK => $_->[0], ID => $_->[1]}, @$ref;
}

1;
