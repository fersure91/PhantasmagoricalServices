#!/usr/bin/env perl
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

use strict;
no strict 'refs';

use constant { # Need them up here, before anybody derefs them.
	ST_PRECONNECT => 0,
	ST_LOADMOD => 1,
	ST_NORMAL => 2,
	ST_SHUTDOWN => 3,
	ST_CLOSED => 4,
	NETDUMP => 0,
};

use Cwd 'abs_path';
use File::Basename;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename;
	my %constants = (
		CWD => getcwd(),
		PREFIX => dirname(abs_path($0)),
	);
	require constant; import constant(\%constants);
}
chdir PREFIX;
use lib PREFIX;

use Getopt::Long;
BEGIN {
	my @debug_pkgs;
	my $compile_only = 0;

	GetOptions(
		"debug:s" => \@debug_pkgs,
		"compile" => \$compile_only,
	);

	if(@debug_pkgs) {
		require SrSv::Debug;

		SrSv::Debug::enable();
		push @debug_pkgs, 'main';
		foreach my $pkg (@debug_pkgs) {
			$SrSv::Debug::debug_pkgs{$pkg} = 1;
		}
	}
	import constant { COMPILE_ONLY => $compile_only };
}

use SrSv::Conf::Parameters main => [
	qw(local remote port numeric pass load email replyto),
	[info => 'SurrealServices'],
	[procs => 4],
	[diag => '#Diagnostics'],
	[netname => 'Network'],
	[sig => 'Thank you for chatting with us.'],
	[unsyncserver => undef],
	[nomail => undef],
	[logmail => undef],
	[hashed_passwords => undef],
];

use SrSv::OnIRC (1);

use SrSv::Debug;
use SrSv::Log;
use SrSv::Conf2Consts qw(main);

use IO::Socket;
use Carp;

use SrSv::IRCd::IRCdSpecific; # <-- is package ircd
#use libs::config;
use libs::misc;
use libs::event;
use libs::modes;
use libs::module;

# This is only here for compile checking. NEVER enable it for anything else.
#use modules::services;

use SrSv::Process::Init ();
use SrSv::Process::Worker qw(spawn);
use SrSv::Message qw(add_callback);
use SrSv::Timer qw(begin_timer);

#*conf = \%main_conf; #FIXME

STDOUT->autoflush(1);

our $progname = 'SurrealServices';
our $version = '0.4.3-pre';
our $extraversion = 'configured for UnrealIRCd 3.2.7';

#FIXME: Figure out where $rsnick belongs and update all references
our $rsnick; *rsnick = \$core::rsnick;

print "Starting $progname $version.\n";

#config::loadconfig();

module::load();
exit() if COMPILE_ONLY;
ircd::serv_connect();

unless(DEBUG) {
	exit if fork;
	close STDIN;
	close STDOUT;
	close STDERR;
	open STDIN, '<', '/dev/null';
	open STDOUT, '>', '/dev/null';
	open STDERR, '>', '/dev/null';
	setpgrp();
}

if(main_conf_procs) {
	for(1..main_conf_procs) { spawn(); }
}

SrSv::Process::Init::do_init();
module::begin();

begin_timer();

event::loop();
