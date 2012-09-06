#!/usr/bin/perl

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

#  SurrealChat.net does not provide the Country/Allocation data,
#  is in no way associated with maxmind.com,
#  nor are we providing a license to download/use it.
#  Be sure to direct availability/accuracy/licensing questions to maxmind.com

use strict;
#use warnings;
use DBI;

BEGIN {
	use Cwd qw( abs_path getcwd );
	use File::Basename;
	my %constants = (
		CWD => getcwd(),
		PREFIX => abs_path(dirname(abs_path($0)).'/..'),
	);
	require constant; import constant(\%constants);
}
#chdir PREFIX;
use lib PREFIX;

use Date::Parse;
use Text::ParseWords; # is a standard (in 5.8) module

use SrSv::Conf2Consts qw( sql );
use SrSv::Util qw( :say );

sub runSQL($@) {
	my ($dbh, @strings) = @_;
	foreach my $string (@strings) {
		my $sql;
		foreach my $x (split($/, $string)) { $sql .= $x unless $x =~ /^(#|--)/ or $x eq "\n"}
#		$dbh->do("START TRANSACTION");
		my $printError = $dbh->{PrintError};
		$dbh->{PrintError} = 0;
		foreach my $line (split(/;/s, $sql)) {
			next unless length($line);
			#print "$line\n";
			eval { $dbh->do($line); };
			if($@) {
				$line =~ s/\s{2,}/ /g;
				$line =~ s/\n//g;
				print "$line\n";
			}
			
		}
		$dbh->{PrintError} = $printError;
#		$dbh->do("COMMIT");
	}
}

BEGIN {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime();
	$year += 1900;
	$mon++; # gmtime returns months January=0
	my $date = sprintf("%04d%02d01", $year, $mon);
	require constant;
	import constant {
		#countrydb_url =>  'http://www.maxmind.com/download/geoip/database/GeoIPCountryCSV.zip',
		#FIXME: This needs a date generator!
		countrydb_url => "http://www.maxmind.com/download/geoip/database/GeoLiteCity_CSV/GeoLiteCity_${date}.zip",
		srcname => "GeoLiteCity_${date}.zip",
	};
}

sub main() {
	downloadData();
	say "Connecting to database...";
	my $dbh = dbConnect();
	say "Creating new table...";
	newTable($dbh);
	say "Inserting data...     ";
	loadData($dbh);
	say "Converting geoip table...     ";
	convert($dbh);
	cleanup($dbh);
	$dbh->disconnect();
	say "GeoIP update complete.";
}

main();
exit 0;

sub downloadData() {
	# This MAY be implementable with an open of a pipe
	# pipe the output of wget through gzip -d
	# and then into the load-loop.
	# It's a bit heavy to run directly from inside services however.
	# I'd recommend it be run as a crontab script separate from services.

	#return;
	my ($stat, $date, $size);
	my $srcPath = PREFIX.'/data/'.srcname;
	say $srcPath;
	use File::stat;
	if($stat = stat($srcPath)) {
		print "Checking for updated country data...\n";
		my $header = qx "wget --spider -S @{[countrydb_url]} 2>&1";
		($date) = ($header =~ /Last-Modified: (.*)/);
		($size) = ($header =~ /Content-Length: (.*)/);
	}

	if($stat and $stat->size == $size and $stat->mtime >= str2time($date)) {
		say "Country data is up to date.";
	} else {
#		say $stat->size == $size;
#		say $stat->mtime >= str2time($date);
		say "Downloading country data...";
#		return;

		unlink $srcPath;
		system('wget '.countrydb_url." -O $srcPath");
		unless(-e $srcPath) {
			sayERR "FATAL: Download failed.";
			exit;
		}
	}

	mkdir PREFIX.'/data/GeoIP/';
	say "Decompressing...";
	unlink(glob(PREFIX.'/data/GeoIP/Geo*.csv'));
	system("unzip -j $srcPath -d ".PREFIX.'/data/GeoIP/');
	unless(-f PREFIX.'/data/GeoIP/GeoLiteCity-Blocks.csv') {
		sayERR "FATAL: Decompression failed.";
		exit -1;
	}
}

sub dbConnect() {
	my $dbh;
	eval { 
		$dbh = DBI->connect("DBI:mysql:".sql_conf_mysql_db, sql_conf_mysql_user, sql_conf_mysql_pass,
			{  AutoCommit => 1, RaiseError => 1 })
	};

	if($@) {
		print STDERR "FATAL: Can't connect to database:\n$@\n";
		print STDERR "You must edit config/sql.conf and create a corresponding\nMySQL user and database!\n\n";
		exit -1;
	}
	return $dbh;
}

sub newTable($) {
	my ($dbh) = @_;
	$dbh->{RaiseError} = 1;
	$dbh->{PrintError} = 1;

	runSQL($dbh, 
		"DROP TABLE IF EXISTS new_geoip",
		"CREATE TABLE `new_geoip` (
		  `low` int unsigned NOT NULL default 0,
		  `high` int unsigned NOT NULL default 0,
		  `location` int NOT NULL default '0',
		  PRIMARY KEY (`low`, `high`)
		) TYPE=MyISAM",
		
		"DROP TABLE IF EXISTS new_geolocation",
	#"locId,country,region,city,postalCode,latitude,longitude,metroCode,areaCode";
		"CREATE TABLE `new_geolocation` (
		  `id` int unsigned NOT NULL default 0,
		  `country` char(2) NOT NULL default '-',
		  `region` char(2) NOT NULL default '-',
		  `city` varchar(255) NOT NULL default '-',
		  `postalcode` varchar(6) NOT NULL default '-',
		  `latitude` float NOT NULL default 0.0,
		  `longitude` float NOT NULL default 0.0,
		  `metrocode` int unsigned NOT NULL default 0,
		  `areacode` int unsigned NOT NULL default 0,
		  PRIMARY KEY (`id`),
		  KEY `countrykey` (`country`)
		  ) TYPE=MyISAM;",
		  
	 	  "DROP TABLE IF EXISTS `new_metrocode`",
		  "CREATE TABLE `new_metrocode` (
		    `id` smallint NOT NULL default 0,
		    `metro` varchar(128) NOT NULL default '',
		    PRIMARY KEY (`id`)
		  ) TYPE=MyISAM;",

		"DROP TABLE IF EXISTS `new_geocountry`",
	#"locId,country,region,city,postalCode,latitude,longitude,metroCode,areaCode";
		"CREATE TABLE `new_geocountry` (
		  `code` char(2) NOT NULL default '',
		  `country` varchar(255) default '',
		  PRIMARY KEY (`code`)
		  ) TYPE=MyISAM;",

		"DROP TABLE IF EXISTS `new_georegion`",
	#"locId,country,region,city,postalCode,latitude,longitude,metroCode,areaCode";
		"CREATE TABLE `new_georegion` (
		  `country` char(2) NOT NULL default '',
		  `region` char(2) NOT NULL default '',
		  `name` varchar(255) default '',
		  PRIMARY KEY (`country`, `region`)
		  ) TYPE=MyISAM;",

	);
}

sub loadData($) {
	my ($dbh) = @_;
	$| = 1;
=cut
	my $unpackPath = PREFIX.'/data/'.unpackname;
	my ($lines) = qx{wc -l $unpackPath};
	my $div = int($lines/100);
=cut
	my ($i, @entries);
	my $fh;
	my $table;

	print "Loading geoip data...";
####### geoip #######
	open ($fh, '<', PREFIX.'/data/GeoIP/GeoLiteCity-Blocks.csv');
	$table = 'geoip';
	#my $add_entry = $dbh->prepare("INSERT INTO `new_geoip` (low, high, location) VALUES (?,?,?)");
	runSQL($dbh,
#		"LOCK TABLES `new_geoip` WRITE, `new_geolocation` WRITE,
#			`new_metrocode` WRITE, `new_georegion` WRITE, `new_geocountry` WRITE",
		"ALTER TABLE `new_$table` DISABLE KEYS",
	);

	my $columns = '(low, high, location)';
	<$fh>; <$fh>; # pop first 2 lines off.
	while(my $x = <$fh>) {
		chomp $x;
=cut
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
=cut	
		my @args = split(',', $x);
		push @entries, '(' . join(',', @args) . ')' if scalar(@args) == 3;
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	$dbh->do(("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries))) if scalar(@entries);
	$dbh->do("ALTER TABLE `new_$table` ENABLE KEYS");
	@entries = ();
	close $fh;
####### END geoip #######
	say " Done.";

	print "Loading location data...";
####### locations #######
	$table = 'geolocation';
	$columns = "(`id`, `country`, `region`, `city`, `postalcode`, `latitude`, `longitude`, `metrocode`, `areacode`)";
	open ($fh, '<', PREFIX.'/data/GeoIP/GeoLiteCity-Location.csv');

	$dbh->do("ALTER TABLE `new_$table` DISABLE KEYS");

	<$fh>; <$fh>; # pop first 2 lines off.
	while(my $x = <$fh>) {
		chomp $x;
=cut
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
=cut	
		my @args = map( { $dbh->quote($_) } parse_line(",\\s*", 0, $x) );
		push @entries, '(' . join(',', @args) . ')' if scalar(@args) == 9;
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	$dbh->do(("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries))) if scalar(@entries);
	@entries = ();
	$dbh->do("ALTER TABLE `new_$table` ENABLE KEYS");
	close $fh;
####### END locations #######
	say " Done.";


	print "Loading metrocode data...";
####### metrocodes #######
	open ($fh, '<', PREFIX.'/data/GeoIP/metrocodes.txt');
	$table = 'metrocode';
	$columns = "(`id`, `metro`)";

	$dbh->do("ALTER TABLE `new_$table` DISABLE KEYS");

	while(my $x = <$fh>) {
		chomp $x;
=cut
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
=cut	
		my @args = map( { $dbh->quote($_) } split(' ', $x, 2) );
		push @entries, '(' . join(',', @args) . ')' if scalar(@args) == 2;
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	$dbh->do(("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries))) if scalar(@entries);
	@entries = ();
	$dbh->do("ALTER TABLE `new_$table` ENABLE KEYS");
	close $fh;
####### END metrocodes #######
	say " Done.";

	print "Loading region data...";
####### regions #######
	$table = 'georegion';
	$columns = "(`country`, `region`, `name`)";

	$dbh->do("ALTER TABLE `new_$table` DISABLE KEYS");
	open ($fh, '<', PREFIX.'/data/fips10_4');
	<$fh>; # pop first line off.
	while(my $x = <$fh>) {
		chomp $x;
=cut
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
=cut	
		my @args = map( { $dbh->quote($_) } parse_line(",\\s*", 0, $x) );
		push @entries, '(' . join(',', @args) . ')' if scalar(@args) == 3;
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	close $fh;

	open ($fh, '<', PREFIX.'/data/iso3166_2');
	<$fh>; # pop first line off.
	while(my $x = <$fh>) {
		chomp $x;
=cut
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
=cut	
		my @args = map( { $dbh->quote($_) } parse_line(",\\s*", 0, $x) );
		push @entries, '(' . join(',', @args) . ')' if scalar(@args) == 3;
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	close $fh;
	$dbh->do(("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries))) if scalar(@entries);
	@entries = ();
	$dbh->do("ALTER TABLE `new_$table` ENABLE KEYS");
####### END regions #######
	say " Done.";

	print "Loading country data...";
####### iso3166 Country Names #######
	open ($fh, '<', PREFIX.'/data/iso3166');
	$table = 'geocountry';
	$columns = "(`code`, `country`)";

	$dbh->do("ALTER TABLE `new_$table` DISABLE KEYS");

	while(my $x = <$fh>) {
		chomp $x;
=cut
		if($i == 0 or !($i % $div)) {
			printf("\b\b\b\b%3d%", ($i/$lines)*100);
		}
=cut	
		my @args = map( { $dbh->quote($_) } parse_line(",\\s*", 0, $x) );
		push @entries, '(' . join(',', @args) . ')' if scalar(@args) == 2;
		if(scalar(@entries) >= 100) { #1000 only gives another 10% boost for 10x as much memory
			$dbh->do("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries));
			@entries = ();
		}

		$i++;
	}
	$dbh->do(("INSERT DELAYED INTO `new_$table` $columns VALUES ".join(',', @entries))) if scalar(@entries);
	@entries = ();
	$dbh->do("ALTER TABLE `new_$table` ENABLE KEYS");
	close $fh;
####### END iso3166 Country Names #######
	say " Done.";


#	$dbh->do("UNLOCK TABLES");
}

sub convert($) {
	my ($dbh) = @_;

	runSQL($dbh, 
		"DROP TABLE IF EXISTS `tmp_geoip`",
		"RENAME TABLE `new_geoip` TO `tmp_geoip`",
		"CREATE TABLE `new_geoip` (
		  `low` int unsigned NOT NULL default 0,
		  `high` int unsigned NOT NULL default 0,
		  `location` int NOT NULL default '0',
		  `ip_poly` polygon not null,
		  PRIMARY KEY (`low`, `high`),
		  SPATIAL INDEX (`ip_poly`)
		) TYPE=MyISAM",
		"ALTER TABLE `new_geoip` DISABLE KEYS",
		"INSERT DELAYED INTO new_geoip (low,high,location,ip_poly)
			SELECT low, high, location,
			GEOMFROMWKB(POLYGON(LINESTRING( POINT(low, -1), POINT(high, -1),
			POINT(high, 1), POINT(low, 1), POINT(low, -1)))) FROM tmp_geoip;",
		"ALTER TABLE `new_geoip` ENABLE KEYS",
		"DROP TABLE IF EXISTS `tmp_geoip`",
	);
}

sub cleanup($) {
	my ($dbh) = @_;

#	print "\b\b\b\bdone.\nRemoving old table...\n";
	$dbh->do("DROP TABLE IF EXISTS `oldcountry`");
	say "Renaming new tables...";
	$dbh->{RaiseError} = 0;
	$dbh->{PrintError} = 0;
	$dbh->do("OPTIMIZE TABLE `new_geoip`");
	$dbh->do("ANALYZE TABLE `new_geoip`");
	# Doing the renames cannot be done atomically
	# as sometimes `country` doesn't exist yet.
	$dbh->do("START TRANSACTION");
	$dbh->do("RENAME TABLE `geoip` TO `old_geoip`");
	$dbh->do("RENAME TABLE `new_geoip` TO `geoip`");

	$dbh->do("RENAME TABLE `geolocation` TO `old_geolocation`");
	$dbh->do("RENAME TABLE `new_geolocation` TO `geolocation`");

	$dbh->do("RENAME TABLE `metrocode` TO `old_metrocode`");
	$dbh->do("RENAME TABLE `new_metrocode` TO `metrocode`");

	$dbh->do("RENAME TABLE `georegion` TO `old_georegion`");
	$dbh->do("RENAME TABLE `new_georegion` TO `georegion`");

	$dbh->do("RENAME TABLE `geocountry` TO `old_geocountry`");
	$dbh->do("RENAME TABLE `new_geocountry` TO `geocountry`");

	$dbh->do("DROP TABLE `old_geoip`");
	$dbh->do("DROP TABLE `old_geolocation`");
	$dbh->do("DROP TABLE `old_metrocode`");
	$dbh->do("DROP TABLE `old_georegion`");
	$dbh->do("DROP TABLE `old_geocountry`");
	$dbh->do("COMMIT");
	#unlink PREFIX.'/data/'.unpackname;
}
