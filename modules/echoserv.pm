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
package echoserv;

event::addhandler('PRIVMSG', undef, 'echoserv', __PACKAGE__, 'echoserv::ev_privmsg');
sub ev_privmsg { ircd::privmsg($_[1], $_[0], $_[2]) }

event::addhandler('NOTICE', undef, 'echoserv', __PACKAGE__, 'echoserv::ev_notice');
sub ev_notice { ircd::notice($_[1], $_[0], $_[2]) }

event::addhandler('SEOS', undef, undef, __PACKAGE__, 'echoserv::ev_connect');
sub ev_connect {  ircd::agent_connect('EchoServ', 'services', 'services.SC.net', '+pqzBGHS', 'Echo Server'); }

sub init { }
sub begin { }
sub end { }
sub unload { }

1;
