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
package adminserv;

use strict;

use SrSv::Agent;

use SrSv::Text::Format qw(columnar);
use SrSv::Errors;

use SrSv::User qw(get_user_nick get_user_id);
use SrSv::User::Notice;
use SrSv::Help qw( sendhelp );

use SrSv::Log;

use SrSv::NickReg::Flags qw(NRF_NOHIGHLIGHT nr_chk_flag_user);

#use SrSv::MySQL '$dbh';

use constant {
	S_HELP => 1,
	S_OPER => 2,
	S_ADMIN => 3,
	S_ROOT => 4,
};

# BE CAREFUL CHANGING THESE
my @flags = (
	'SERVOP',
	'FJOIN',
	'SUPER',
	'HOLD',
	'FREEZE',
	'BOT',
	'QLINE',
	'KILL',
	'HELP',
);
my $allflags = (2**@flags) - 1;
my %flags;
for(my $i=0; $i<@flags; $i++) {
	$flags{$flags[$i]} = 2**$i;
}

our $asnick_default = 'AdminServ';
our $asnick = $asnick_default;

our @levels = ('Normal User', 'HelpOp', 'Operator', 'Administrator', 'Root');
my @defflags = (
	0, # Unused
	$flags{HELP}, # HelpOp
	$flags{HELP}|$flags{FJOIN}|$flags{QLINE}|$flags{SUPER}|$flags{FREEZE}|$flags{KILL}, # Operator
	$flags{HELP}|$flags{FJOIN}|$flags{QLINE}|$flags{SUPER}|$flags{FREEZE}|$flags{HOLD}|$flags{BOT}|$flags{SERVOP}|$flags{KILL}, # Admin
	$allflags # Root
);

our (
	$create_svsop, $delete_svsop, $rename_svsop,

	$get_svs_list, $get_all_svsops,

	$get_svs_level, $set_svs_level, $get_best_svs_level,

	$chk_pass, $get_pass, $set_pass
);

sub init() {
	$create_svsop = undef; #$dbh->prepare("INSERT IGNORE INTO svsop SELECT id, NULL, NULL FROM nickreg WHERE nick=?");
	$delete_svsop = undef; #$dbh->prepare("DELETE FROM svsop USING svsop, nickreg WHERE nickreg.nick=? AND svsop.nrid=nickreg.id");

	$get_svs_list = undef; #$dbh->prepare("SELECT nickreg.nick, svsop.adder FROM svsop, nickreg WHERE svsop.level=? AND svsop.nrid=nickreg.id ORDER BY nickreg.nick");
	$get_all_svsops = undef; #$dbh->prepare("SELECT nickreg.nick, svsop.level, svsop.adder FROM svsop, nickreg WHERE svsop.nrid=nickreg.id ORDER BY svsop.level, nickreg.nick");

	$get_svs_level = undef; #$dbh->prepare("SELECT svsop.level FROM svsop, nickalias WHERE nickalias.alias=? AND svsop.nrid=nickalias.nrid");
	$set_svs_level = undef; #$dbh->prepare("UPDATE svsop, nickreg SET svsop.level=?, svsop.adder=? WHERE nickreg.nick=? AND svsop.nrid=nickreg.id");
	$get_best_svs_level = undef; #$dbh->prepare("SELECT svsop.level, nickreg.nick FROM nickid, nickreg, svsop WHERE nickid.nrid=nickreg.id AND svsop.nrid=nickreg.id AND nickid.id=? ORDER BY level DESC LIMIT 1");

	$chk_pass = undef; #$dbh->prepare("SELECT 1 FROM ircop WHERE nick=? AND pass=?");
	$get_pass = undef; #$dbh->prepare("SELECT pass FROM ircop WHERE nick=?");
	$set_pass = undef; #$dbh->prepare("UPDATE ircop SET pass=? WHERE nick=?");
}

### ADMINSERV COMMANDS ###

sub dispatch($$$) {
	my ($src, $dst, $msg) = @_;
	$msg =~ s/^\s+//;
	my @args = split(/\s+/, $msg);
	my $cmd = shift @args;

	my $user = { NICK => $src, AGENT => $dst };

	services::ulog($asnick, LOG_INFO(), "cmd: [$msg]", $user);

	unless(is_svsop($user) or is_ircop($user)) {
		notice($user, $err_deny);
		ircd::globops($asnick, "\002$src\002 failed access to $asnick $msg");
		return;
	}

	if($cmd =~ /^svsop$/i) {
		my $cmd2 = shift @args;
		
		if($cmd2 =~ /^add$/i) {
			if(@args == 2 and $args[1] =~ /^[aoh]$/i) {
				as_svs_add($user, $args[0], num_level($args[1]));
			} else {
				notice($user, 'Syntax: SVSOP ADD <nick> <A|O|H>');
			}
		}
		elsif($cmd2 =~ /^del$/i) {
			if(@args == 1) {
				as_svs_del($user, $args[0]);
			} else {
				notice($user, 'Syntax: SVSOP DEL <nick>');
			}
		}
		elsif($cmd2 =~ /^list$/i) {
			if(@args == 1 and $args[0] =~ /^[raoh]$/i) {
				as_svs_list($user, num_level($args[0]));
			} else {
				notice($user, 'Syntax: SVSOP LIST <R|A|O|H>');
			}
		}
		else {
			notice($user, 'Syntax: SVSOP <ADD|DEL|LIST> [...]');
		}
	}
	elsif($cmd =~ /^whois$/i) {
		if(@args == 1) {
			as_whois($user, $args[0]);
		} else {
			notice($user, 'Syntax: WHOIS <nick>');
		}
	}
	elsif($cmd =~ /^help$/i) {
		sendhelp($user, 'adminserv', @args)
	}
	elsif($cmd =~ /^staff$/i) {
		if(@args == 0) {
			as_staff($user);
		}
		else {
			notice($user, 'Syntax: STAFF');
		}
	}
	else {
		notice($user, "Unrecognized command.  For help, type: \002/msg adminserv help\002");
	}
}

sub as_svs_add($$$) {
	my ($user, $nick, $level) = @_;
	my $src = get_user_nick($user);

	my ($root, $oper) = validate_chg($user, $nick);
	return unless $oper;

	if(get_svs_level($root) >= S_ROOT) {
		notice($user, $err_deny);
		return;
	}

	$create_svsop->execute($root);
	$set_svs_level->execute($level, $oper, $root);
	
	notice($user, "\002$nick\002 is now a \002Services $levels[$level]\002.");
	wlog($asnick, LOG_INFO(), "$src added $root as a Services $levels[$level].");
}

sub as_svs_del($$) {
	my ($user, $nick) = @_;
	my $src = get_user_nick($user);

	my ($root, $oper) = validate_chg($user, $nick);
	return unless $oper;

	if(get_svs_level($root) >= S_ROOT) {
		notice($user, $err_deny);
		return;
	}
	
	$delete_svsop->execute($root);
	notice($user, "\002$nick\002 has been stripped of services rank.");
	wlog($asnick, LOG_INFO(), "$src stripped $root of services rank.")
}

sub as_svs_list($$) {
	my ($user, $level) = @_;
	my (@data, @reply);

	$get_svs_list->execute($level);
	
	while(my ($nick, $adder) = $get_svs_list->fetchrow_array) {
		push @data, [$nick, "($adder)"];
	}
	
	notice($user, columnar({TITLE => "Services $levels[$level] list:",
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data));
}

sub as_whois($$) {
	my ($user, $nick) = @_;
	
	my ($level, $root) = get_best_svs_level({ NICK => $nick });
	notice($user, "\002$nick\002 is a Services $levels[$level]".($level ? ' due to identification to the nick '."\002$root\002." : ''));
}

sub as_staff($) {
	my ($user) = @_;
	my (@data);

	$get_all_svsops->execute();
	
	while(my ($nick, $level, $adder) = $get_all_svsops->fetchrow_array) {
		push @data, [$nick, $levels[$level], "($adder)"];
	}
	
	notice($user, columnar({TITLE => 'Staff list:',
		NOHIGHLIGHT => nr_chk_flag_user($user, NRF_NOHIGHLIGHT)}, @data));
}


### DATABASE UTILITY FUNCTIONS ###

sub validate_chg($$) {
	my ($user, $nick) = @_;
	my ($oper);

	unless($oper = is_svsop($user, S_ROOT)) {
		notice($user, $err_deny);
		return undef;
	}

	my $root = nickserv::get_root_nick($nick);
	unless($root) {
		notice($user, "The nick \002$nick\002 is not registered.");
		return undef;
	}

	return ($root, $oper);
}

sub can_do($$) {
	my ($user, $flag) = @_;
	my $nflag = $flags{$flag};
	
	my ($level, $nick) = get_best_svs_level($user);
	
	if($defflags[$level] & $nflag) {
		return $nick if (($nflag == $flags{'HELP'}) or is_ircop($user));
	}
	
	return undef;
}

sub is_svsop($;$) {
	my ($user, $rlev) = @_;

	my ($level, $nick) = get_best_svs_level($user);
	return $nick if(defined($level) and !defined($rlev));

	if($level >= $rlev) {
		return $nick if (($rlev == S_HELP) or is_ircop($user));
	}
	
	return undef;
}

sub is_ircop($) {
	my ($user) = @_;

	return undef if is_agent($user->{NICK});

	return $user->{IRCOP} if(exists($user->{IRCOP}));

	my %umodes = modes::splitumodes(nickserv::get_user_modes($user));

	no warnings 'deprecated';
	if(($umodes{'o'} eq '+') or ($umodes{'S'} eq '+')) {
		$user->{IRCOP} = 1;
	}
	else {
		$user->{IRCOP} = 0;
	}

	return $user->{IRCOP};
}

sub is_service($) {
# detect if a user belongs to another service like NeoStats. only works if they set umode +S
# is_ircop() includes is_service(), so no reason to call both.
	my ($user) = @_;

	return undef if is_agent($user->{NICK});

	return $user->{SERVICE} if(exists($user->{SERVICE}));

	my %umodes = modes::splitumodes(nickserv::get_user_modes($user));

	if($umodes{'S'} eq '+') {
		$user->{SERVICE} = 1;
		$user->{IRCOP} = 1;
	}
	else {
		$user->{SERVICE} = 0;
	}

	return $user->{SERVICE};
}

sub get_svs_level($) {
	my ($nick) = @_;

	return undef if is_agent($nick);

	$get_svs_level->execute($nick);
	my ($level) = $get_svs_level->fetchrow_array;

	return $level or 0;
}

sub get_best_svs_level($) {
	my ($user) = @_;
	
	return undef if is_agent($user->{NICK});

	if(exists($user->{SVSOP_LEVEL}) && exists($user->{SVSOP_NICK})) {
		if(wantarray) {
			return ($user->{SVSOP_LEVEL}, $user->{SVSOP_NICK});
		} else {
			return $user->{SVSOP_LEVEL};
		}
	}
	
	my $uid = get_user_id($user);
	$get_best_svs_level->execute($uid);
        my ($level, $nick) = $get_best_svs_level->fetchrow_array;

	$user->{SVSOP_LEVEL} = $level; $user->{SVSOP_NICK} = $nick;
	
	if(wantarray) {
		return ($level, $nick);
	} else {
		return $level;
	}
}

### MISCELLANEA ###

sub num_level($) {
	my ($x) = @_;
	$x =~ tr/hoarHOAR/12341234/;
	return $x;
}

### IRC EVENTS ###

1;
