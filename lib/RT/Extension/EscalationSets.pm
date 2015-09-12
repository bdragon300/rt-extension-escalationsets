package RT::Extension::EscalationSets;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.1';

=head1 NAME

RT::Extension::EscalationSets - Different escalation rules (sets) 
for different tickets

=head1 DESCRIPTION

Central concept is "set", that logically groups SLA time and escalation levels
with their timeouts. You can apply different escalation sets to tickets
depending on things in --search or --condition in rt-crontool, such as TicketSQL
or Overdue. So you can tune ticket escalation more particularly.

The extension checks tickets periodically (via rt-crontool) using name of set
passed as argument. If necessary the escalation process will be performed
automatically to reach needed level. Extension can write comment, send email
about level change. Each level can calculate based on Created, Due ticket
fields. Current escalation level and set store in appropriate Custom Fields.

Also the extension can set Due field for each set separately (if specified in
config). If ticket will move to another escalation set then Due will be
recalculated. If Due was set before extension "saw" the ticket then it doesn't
touch Due anymore but escalation will work. This allows specify another Due
value manually or by another scrip, for example.

The extension supports pausing SLA time (such as stalled status, etc.). When
ticket goes into "paused" state the Due must be unset and then the extension
must not "see" the ticket until it will come from "paused" state. When this
happened the Due automatically recalculated.

You can create set that will not use Due. In this case the escalation will be
performed simply based on Created (B<_dueinterval> is not specified, see below).
"Pausing" tickets will not support, i.e. SLA time will be continuous.

=head1 DEPENDENCIES

=over

=item RT >= 4.2.0

=item Date::Manip >= 6.25

=back

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

=item Edit your RT_SiteConfig.pm

If you are using RT 4.2 or greater, add this line:

    Plugin('RT::Extension::EscalationSets');

For RT 3.8 and 4.0, add this line:

    Set(@Plugins, qw(RT::Extension::EscalationSets));

or add C<RT::Extension::EscalationSets> to your existing C<@Plugins> line.

=item Restart your webserver

=back

=head1 CONFIGURATION AND EXAMPLES

See README.md

=head1 AUTHOR

Igor Derkach, E<lt>gosha753951@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Igor Derkach, E<lt>https://github.com/bdragon300/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.

=head1 METHODS

newDateObj DATE, TIMEZONE

Creates new Date::Manip::Date object from DATE and return its converted to
TIMEZONE

=cut

sub newDateObj {
    my $self = shift;
    my $val = shift;
    my $tz = shift;

    my $obj = new Date::Manip::Date;
    $obj->config('setdate', 'zone,UTC');
    $obj->parse($val);
    $obj->convert($tz);

    return $obj;
}

# This function exists because Date::Manip::Date::cmp sometimes not properly works
sub cmpDates {
    my $self = shift;
    my $a = shift;
    my $b = shift;

    return ($a->printf("%s") cmp $b->printf("%s"));
}

1;