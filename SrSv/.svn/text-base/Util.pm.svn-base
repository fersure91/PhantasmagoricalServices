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

package SrSv::Util;

use strict;

use Exporter 'import';
BEGIN {
	our @EXPORT = qw(min max makeSeqList);
	our @EXPORT_OK = qw(
		say say2 say3 sayFH sayERR
		slurpFile dumpFile
		interpretSuffixes humanizeBigNums
	);
	our %EXPORT_TAGS = (
		say => [qw( say say2 say3 sayFH sayERR )],
	);
		
}

sub min($$) {
	return ($_[0] < $_[1] ? $_[0] : $_[1]);
}
sub max($$) {
	return ($_[0] > $_[1] ? $_[0] : $_[1]);
}

sub makeSeqList(@) { 
	my @nums;
	foreach my $arg (@_) {
		foreach my $parm (split(',', $arg)) {
			if ($parm =~ /^(\d+)(?:-|\.\.)(\d+)$/) {
				push @nums, min($1, $2)..max($1, $2);
			} elsif(misc::isint($parm)) {
				push @nums, $parm;
			} else {
				# just ignore it. we could try throwing an error.
			}
		}
	}
	# map is a uniqify in case of duplicates
	# the sort is modified to sort numerically rather than by string.
	return sort( {$a <=> $b}  keys %{{ map { $_ => 1 } @nums }} );
}

sub __say($@) {
	my ($chr, @list) = @_;
	return join( '', map( {"$_$chr"} @list) );
}
sub _say(@) {
	return __say ("\n", @_);
}
sub say(@) {
	print _say(@_);
}
sub sayFH($@) {
	my ($fh, @list) = @_;
	print $fh _say(@list);
}
sub sayERR(@) {
	sayFH STDERR, @_;
}
sub say2(@) {
	say( __say( ' ', @_) );
}
sub say3(@) {
	say(  __say( ',', map({"\"$_\"" } @_) ) );
}

sub slurpFile($) {
	my ($filename) = @_;
	open((my $fh), '<', $filename) or return;
	binmode $fh;
	local $/;
	my $data = <$fh>;
	close $fh;
	return $data;
}

sub dumpFile($@) {
	my ($filename, @data) = @_;
	open((my $fh), '>', $filename);
	binmode $fh;
	print $fh join("\n", map({ chomp $_; $_ } @data));
	close $fh;
}

my %suffixes = ( 'k' => 1024, 'm' => 1048576, 'g' => 1024**3, 't' => 1024**4 );
sub interpretSuffixes($) {
	my ($mem) = @_;
	$mem =~ /^(\d+)\s*([kmgt])?(?:i?B)?$/i;
	my ($num, $suffix) = ($1, $2);
	if($suffix) {
		return $num * $suffixes{lc $suffix};
	} else {
		return $num;
	}
}

sub humanizeBigNums($;$) {
	my ($val, $precision) = @_;
	$precision = 2 unless $precision;
	#return $val;
	#return sprintf("%.2gMiB", $val / (1 << 20));
	if($val > (1 << 40)) {
		return sprintf("%.${precision}fTiB", $val / (1 << 40));
	}
	elsif($val > (1 << 30)) {
		return sprintf("%.${precision}fGiB", $val / (1 << 30));
	}
	elsif($val > (1 << 20)) {
		return sprintf("%.${precision}fMiB", $val / (1 << 20));
	}
	elsif($val > (1 << 10)) {
		return sprintf("%.${precision}fKiB", $val / (1 << 10));
	}
}

1;
