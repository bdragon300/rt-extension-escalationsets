package RT::Extension::EscalationSets;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.2';

=head1 NAME

RT::Extension::EscalationSets - Different escalation rules (sets) 
for different tickets

=head1 DESCRIPTION

RequestTracker extension that performs escalation with different 
timeouts for different tickets for example fetched using TicketSQL.
Also you can specify additional actions while escalation performs.

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item C<make initdb>

Only run this the first time you install this module.

If you run this twice, you may end up with duplicate data
in your database.

If you are upgrading this module, check for upgrading instructions
in case changes need to be made to your database.

=item Edit your RT_SiteConfig.pm

If you are using RT 4.2 or greater, add this line:

    Plugin('RT::Extension::SLA');

For RT 3.8 and 4.0, add this line:

    Set(@Plugins, qw(RT::Extension::SLA));

or add C<RT::Extension::SLA> to your existing C<@Plugins> line.

=item Restart your webserver

=back

=head1 CONFIGURATION

See README.md

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.


=cut

sub dm_to_str {
    my $dm = shift; #Date::Manip obj
    my $format = shift;
    my $tz = shift;
    
    return $dm->printf($format) 
        if $dm->printf("%s") eq '0';
    my $obj = new Date::Manip::Date;
    $obj->parse($dm->printf('%Y-%m-%d %T'));
    $obj->convert($tz) 
        if $tz;
        
    return $obj->printf($format);
}

sub str_to_dm {
    my $val = shift;
    my ($from_tz, $to_tz) = ('UTC', '', @_);

    my $obj = new Date::Manip::Date;
    $obj->config('setdate', "zone,$from_tz")
        if $from_tz;
    $obj->parse($val);
    $obj->convert($to_tz) 
        if $to_tz;

    return $obj;
}

# This function exists because Date::Manip::Date::cmp sometimes not properly works
#sub cmpDates {
#    my $self = shift;
#    my $a = shift;
#    my $b = shift;
#
#    return ($a->printf("%s") cmp $b->printf("%s"));
#}

sub load_config {
	my %conf = (
	   EscalationField => RT->Config->Get('EscalationField'),
	   EscalationSetField => RT->Config->Get('EscalationSetField'),
	   EscalationSets => {RT->Config->Get('EscalationSets')}
	);
	return (undef) if (scalar(grep { ! $_ } values %conf));
	return (undef) if ref($conf{'EscalationSets'}) ne 'HASH';
    return \%conf;
}

1;