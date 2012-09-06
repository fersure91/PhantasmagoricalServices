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

package SrSv::MySQL;

use strict;

use Exporter 'import';
BEGIN { our @EXPORT_OK = qw($dbh) }

use DBI;

use SrSv::Process::Init;

use SrSv::Conf::Parameters sql => [
	qw(mysql_user mysql_pass mysql_db),
	[server_prepare => 0],
];

use SrSv::Conf 'sql';

our $dbh;

proc_init {
	$dbh = DBI->connect(
		"DBI:mysql:".$sql_conf{'mysql-db'}.($sql_conf{server_prepare} ? ":mysql_server_prepare=1" : ''),
		$sql_conf{'mysql-user'},
		$sql_conf{'mysql-pass'},
		{
			AutoCommit => 1,
			RaiseError => 0,
			mysql_auto_reconnect => 1,
		}
	);
	# Prevent timeout
	$dbh->do("SET wait_timeout=(86400*365)");
};

1;
