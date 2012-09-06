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
package SrSv::Log;

use strict;
use IO::Handle;

use SrSv::Debug;
use SrSv::Timer qw(add_timer);
use SrSv::Time;
use SrSv::Process::InParent qw(write_log open_log close_log rotate_logs close_all_logs);

use SrSv::Text::Codes qw( strip_codes );

use SrSv::Conf2Consts qw(main);

use Exporter 'import';
BEGIN {
	my %constants = (
		LOG_DEBUG => 0,
		LOG_INFO => 1,
		LOG_WARNING => 2,	# A bad thing might happen
		LOG_ERROR => 3,		# A bad thing happened
		LOG_CRITICAL => 4,	# One module is going down
		LOG_FATAL => 5,		# One thread is going down
		LOG_PANIC => 6,		# The entire server is going down

		LOG_OPEN => 1,
		LOG_CLOSE => 2,
		LOG_WRITE => 3,
		LOG_ROTATE => 4,
	);

	require constant; import constant (\%constants);
	our @EXPORT = ( qw( wlog write_log open_log close_log ), keys(%constants) );
	our @EXPORT_OK = ( qw ( rotate_logs close_all_logs ) );
	our %EXPORT_TAGS = (
		levels => [keys(%constants)],
		all => [@EXPORT, @EXPORT_OK],
	);
}

our $path = './logs';
our @levels = ('DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL', 'FATAL', 'PANIC');

open_log('diag', 'services.log');
open_log('netdump', 'netdump.log') if main::NETDUMP();

sub wlog($$$) {
	my ($service, $level, $text) = @_;

	my $prefix;
	$prefix = "\002\00304" if($level > LOG_INFO);
	$prefix .= $levels[$level];
	ircd::privmsg($main::rsnick, main_conf_diag, "$prefix\: ($service) $text");
	write_log('diag', '<'.$main::rsnick.'>', "$prefix\: ($service) $text");
}

my %log_handles;
my %file_handles;

sub write_log($$@) {
	my ($handle, $prefix, @payloads) = @_;
	unless (defined($log_handles{lc $handle})) {
		ircd::debug_nolog("undefined log-handle $handle, aborting write()") if main::DEBUG();
		return undef;
	}
	foreach (@payloads) {
		$_ = strip_codes($_);
	}
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime();
	my $time = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
	my $payload = $time.$prefix.' '.join("\n".$time.$prefix.' ', @payloads);
	print {$log_handles{lc $handle}} "$payload\n";
}

sub open_log($$) {
	my ($handle, $filename) = @_;
	if (defined($log_handles{lc $handle})) {
		ircd::debug_nolog("duplicate log-handle $handle, aborting open()");
		return undef;
	}
	my ($year, $month, undef, $mday) = gmt_date();
	my $filename2 = $filename.'-'.sprintf('%04d-%02d-%02d', $year, $month, $mday);
	
	open $log_handles{lc $handle}, '>>', $path.'/'.$filename2;
	$file_handles{lc $handle} = { BASENAME => $filename, FILENAME => $filename2 };
	$log_handles{lc $handle}->autoflush(1);
}

sub close_log($) {
	my ($handle) = @_;
	unless (defined($log_handles{lc $handle})) {
		ircd::debug_nolog("undefined log-handle $handle, aborting close()");
		return undef;
	}
	close $log_handles{lc $handle};
	delete($log_handles{lc $handle});
}

sub rotate_logs() {
	foreach my $handle (keys(%file_handles)) {
		close $log_handles{$handle};
		my ($year, $month, undef, $mday) = gmt_date();
		$file_handles{lc $handle}{FILENAME} = $file_handles{lc $handle}{BASENAME}.'-'.sprintf('%04d-%02d-%02d', $year, $month, $mday);
		open $log_handles{$handle}, '>>', $path.'/'.$file_handles{lc $handle}{FILENAME};
	}
	
	add_timer('', get_nextday_time()-time(), __PACKAGE__, 'SrSv::Log::rotate_logs');
}

sub close_all_logs() {
	foreach my $handle (keys(%file_handles)) {
		close $log_handles{$handle};
		$file_handles{lc $handle} = undef;
	}
}

# set a timer to rotate logs on day-change
add_timer('', get_nextday_time()-time(), __PACKAGE__, 'SrSv::Log::rotate_logs');

1;
