package Lxctl::helper;

use strict;
use warnings;

sub fool_proof
{
	use Term::ANSIColor;
	if (! -t STDIN || ! -t STDOUT) {
		print STDERR color 'bold red';
		print STDERR "Warning! Non-interactive terminal. You have 5 seconds to cancel\n";
		print STDERR color 'reset';
		sleep 5;
		return 1;
	}
	
	my ($self) = @_;
	my $expected_answer = "Yes, all harm from this operation will be a result of my stupidity";
	my $answer = "";
	print color 'bold red';
	print "WARNING! ";
	print color 'reset';
	print "You are about to do something really terrible. This action may cause massive data loss.\n";
	print "If you are sure, please enter: \"$expected_answer\" (without quotes, case sensetive)\n";
	chomp($answer = <STDIN>);
	if ("$answer" eq "$expected_answer") {
		print "Have a lot of fun...\n";
	} else {
		die "Aborted!";
	}
}

# Trys to require module, if success, returns 1, otherwise dies.
sub load_module
{
	my ($self, $module) = @_;
	my $dest = "";
	foreach my $path (@INC) {
		if (-e "$path/$module") {
			$dest = "$path/$module";
			last;
		}
	};

	if (!$dest) {
		die "Unsupported command!\nUsage:\nlxctl [action] [vmname] [options]\n\nSee lxctl --man or lxctl --help for more info\n";
	}

	eval {
		require $dest;
	} or do {
		die "$@\n\n";
	};

	return 1;
}

# Delete from config file.
sub delete_config #(filename, option_name)
{
	my ($self, $filename, $what) = @_;
	open(my $file, '<', "$filename") or
		die " Failed to open $filename!\n\n";

	my @content = <$file>;
	my $status = 0;

	close $file;

	@content = grep(!/^$what/, @content);

	open($file, '>', "$filename") or
		die " Failed to open $filename!\n\n";

	print $file @content;

	close $file;

	return $status;
}


# Destructive change for config file.
# Changes OPT="what ever" to OPT=newval
sub change_config #(filename, searchstring, newvalue)
{
	my ($self, $filename, $what, $newval) = @_;
	open(my $file, '<', "$filename") or
		die " Failed to open $filename!\n\n";

	my @content = <$file>;
	my $status = 0;

	close $file;

	open($file, '>', "$filename") or
		die " Failed to open $filename!\n\n";

	for my $line (@content) {
		$status += $line =~ s/($what).*/$1 $newval/g;
		print $file $line;
	}

	print $file "$what $newval\n" if $status == 0;

	close $file;

	return $status;
}


#(filename, optionname, what we'll change, newval)
#useful for files with options: OPT="some thing to change"
# Does non-destructive change of one part of that string
sub modify_config
{
	my ($self, $filename, $option, $what, $newvalue) = @_;
	open(my $file, '<', "$filename") or
		die " Failed to open $filename!\n\n";

	my @content = <$file>;
	my $status = 0;

	close $file;

	open($file, '>', "$filename") or
		die " Failed to open $filename!\n\n";

	for my $line (@content) {
		$status += $line =~ s/^($option)(.*)$what(.*)/$1$2$newvalue$3/g;
		print $file $line;
	}

	close $file;

	return $status;
}

sub get_config #(filename, searchstring)
{
	my ($self, $filename, $what) = @_;
	$what ||= "";
	open(my $file, '<', "$filename") or
		die " Failed to open $filename!\n\n";

	my @content = <$file>;

	close $file;

	for my $line (@content) {
		if ($line =~ s/($what)\s*=*\s*(.+)/$2/) {
			chomp $line;
			return $line;
		}
	}

	return 0;
}

sub cidr2ip #(cidr_bits)
{
	my ($self, $bits) = @_;

	$bits = 2**32 - 2**(32-$bits);
	return dec2ip($bits);
}

sub dec2ip ($) {
    join('.', unpack('C4', pack('N', shift)));
}

sub new
{
	my $class = shift;
	my $self = {};
	bless $self, $class;

	return $self;
}

1;
__END__
=head1 NAME

Lxctl::destroy

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

Man page by Capitan Obvious.

=head2 EXPORT

None by default.

=head2 Exportable constants

None by default.

=head2 Exportable functions

TODO

=head1 AUTHOR

Anatoly Burtsev, E<lt>anatolyburtsev@yandex.ruE<gt>
Pavel Potapenkov, E<lt>ppotapenkov@gmail.comE<gt>
Vladimir Smirnov, E<lt>civil.over@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Anatoly Burtsev, Pavel Potapenkov, Vladimir Smirnov

This library is free software; you can redistribute it and/or modify
it under the same terms of GPL v2 or later, or, at your opinion
under terms of artistic license.

=cut
