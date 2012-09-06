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
package hostserv;

use strict;

use SrSv::Text::Format qw(columnar);
use SrSv::Errors;

use SrSv::HostMask qw(parse_mask);

use SrSv::User qw(get_user_nick get_user_id);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::NickReg::Flags qw(NRF_NOHIGHLIGHT nr_chk_flag_user);
use SrSv::NickReg::User qw(is_identified);

use SrSv::MySQL '$dbh';
use SrSv::MySQL::Glob;

our $hsnick_default = 'HostServ';
our $hsnick = $hsnick_default;

our (
	$set_vhost, $get_vhost, $del_vhost,
	$vhost_chgroot,

	$get_matching_vhosts
);

sub init() {
	$set_vhost = $dbh->prepare("REPLACE INTO vhost SELECT id, ?, ?, ?, UNIX_TIMESTAMP() FROM nickreg WHERE nick=?");
	$get_vhost = $dbh->prepare("SELECT vhost.ident, vhost.vhost FROM vhost, nickalias WHERE nickalias.nrid=vhost.nrid AND nickalias.alias=?");
	$del_vhost = $dbh->prepare("DELETE FROM vhost USING vhost, nickreg WHERE nickreg.nick=? AND vhost.nrid=nickreg.id");

	$get_matching_vhosts = $dbh->prepare("SELECT nickreg.nick, vhost.ident, vhost.vhost, vhost.adder, vhost.time FROM
		vhost, nickreg WHERE vhost.nrid=nickreg.id AND nickreg.nick LIKE ? AND vhost.ident LIKE ? AND vhost.vhost LIKE ? 
		ORDER BY nickreg.nick");
}

sub dispatch($$$) {
	my ($src, $dst, $msg) = @_;
	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;

	my $user = { NICK => $src, AGENT => $dst };

	return if operserv::flood_check($user);

	if(lc $cmd eq 'on') {
		hs_on($user, $src, 0);
	}
	elsif(lc $cmd eq 'off') {
		hs_off($user);
	}
	elsif($cmd =~ /^(add|set(host))?$/i) {
		if (@args == 2) {
			hs_sethost($user, @args);
		}
		else {
			notice($user, 'Syntax: SETHOST <nick> <[ident@]vhost>');
		}
	}
	elsif($cmd =~ /^del(ete)?$/i) {
		if (@args == 1) {
			hs_delhost($user, @args);
		}
		else {
			notice($user, 'Syntax: DELETE <nick>');
		}
	}
	elsif($cmd =~ /^list$/i) {
		if (@args == 1) {
			hs_list($user, @args);
		}
		else {
			notice($user, 'Syntax: LIST <nick!vident@vhost>');
		}
	}	
        elsif($cmd =~ /^help$/i) {
		sendhelp($user, 'hostserv', @args)
        }
	else { notice($user, "Unknown command."); }
}

sub hs_on($$;$) {
	my ($user, $nick, $identify) = @_;
	my $src = get_user_nick($user);
	
	unless(nickserv::is_registered($nick)) {
		notice($user, "Your nick, \002$nick\002, is not registered.");
		return;
	}

	if(!$identify and !is_identified($user, $nick)) {
		notice($user, "You are not identified to \002$nick\002.");
		return;
	}
	
	$get_vhost->execute($nick);
	my ($vident, $vhost) = $get_vhost->fetchrow_array;
	unless ($vhost) {
		notice($user, "You don't have a vHost.") unless $identify;
		return;
	}
	if ($vident) {
		ircd::chgident($hsnick, $src, $vident);
	}
	ircd::chghost($hsnick, $src, $vhost);

	notice($user, "Your vHost has been changed to \002".($vident?"$vident\@":'')."$vhost\002");
}

sub hs_off($) {
	my ($user) = @_;
	my $src = get_user_nick($user);
	
	# This requires a hack that is only known to work in UnrealIRCd 3.2.6 and later.
	ircd::reset_cloakhost($hsnick, $src);

	notice($user, "vHost reset to cloakhost.");
}

sub hs_sethost($$$) {
	my ($user, $target, $vhost) = @_;
	unless(adminserv::is_svsop($user, adminserv::S_OPER())) {
		notice($user, $err_deny);
		return;
	}
	my $rootnick = nickserv::get_root_nick($target);

	unless ($rootnick) {
		notice($user, "\002$target\002 is not registered.");
		return;
	}

	my $vident = '';
	if($vhost =~ /\@/) {
	    ($vident, $vhost) = split(/\@/, $vhost);
	}
	my $src = get_user_nick($user);
	$set_vhost->execute($vident, $vhost, $src, $rootnick);
	
	notice($user, "vHost for \002$target ($rootnick)\002 set to \002".($vident?"$vident\@":'')."$vhost\002");
}

sub hs_delhost($$) {
	my ($user, $target) = @_;
	unless(adminserv::is_svsop($user, adminserv::S_OPER())) {
		notice($user, $err_deny);
		return;
	}
	my $rootnick = nickserv::get_root_nick($target);

	unless ($rootnick) {
		notice($user, "\002$target\002 is not registered.");
		return;
	}

	$del_vhost->execute($rootnick);
	
	notice($user, "vHost for \002$target ($rootnick)\002 deleted.");
}

sub hs_list($$) {
	my ($user, $mask) = @_;

	unless(adminserv::is_svsop($user, adminserv::S_HELP())) {
		notice($user, $err_deny);
		return;
	}

	my ($mnick, $mident, $mhost) = glob2sql(parse_mask($mask));

	$mnick = '%' if($mnick eq '');
	$mident = '%' if($mident eq '');
	$mhost = '%' if($mhost eq '');

	my @data;
	$get_matching_vhosts->execute($mnick, $mident, $mhost);
	while(my ($rnick, $vident, $vhost) = $get_matching_vhosts->fetchrow_array) {
		push @data, [$rnick, ($vident?"$vident\@":'').$vhost];
	}

	notice($user, columnar({TITLE => "vHost list matching \002$mask\002:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data));
}


### MISCELLANEA ###

    
    
## IRC EVENTS ##

1;
