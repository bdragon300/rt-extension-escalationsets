package RT::Extension::EscalationSets;

use 5.010;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT = qw/ str_to_dm  load_config /;

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

## MySQL date time format:
use constant DATE_FORMAT => '%Y-%m-%d %T';

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
    my %args = (
        Val     => undef,
        FromTz  => undef,
        ToTz    => undef,
        Config  => undef,
        @_
    );

    return (undef) 
        unless $args{'Val'};

    my $obj = new Date::Manip::Date;
    
    dm_set_default_config($obj);
    map{ $obj->config($_, $args{'Config'}->{$_}) }
        keys %{$args{'Config'}} 
        if $args{'Config'};
    $obj->config('setdate', "zone," . $args{'FromTz'})
        if $args{'FromTz'};
        
    $obj->parse($args{'Val'});
    
    $obj->convert($args{'ToTz'}) 
        if $args{'ToTz'};

    return $obj;
}

sub dm_set_default_config
{
    my $dmobj = shift;
    
    $dmobj->config('WorkDay24Hr',  1);
    $dmobj->config('WorkDayBeg',  '00:00');
    $dmobj->config('WorkDayEnd',  '24:00');
    $dmobj->config('WorkWeekBeg',  1);
    $dmobj->config('WorkWeekEnd',  7);
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

sub RT::Ticket::get_datemanip_date
{
    my $self = shift;
    my $field = shift;
    
    return (undef) unless $self->_Accessible($field, 'read');
    return str_to_dm($self->_Value($field));
}

sub RT::Ticket::get_datemanip_delta
{
    my $self = shift;
    my $field = shift;
    my $base = shift // str_to_dm(Val => "now", ToTz => "UTC");
    
    return (undef) unless $self->_Accessible($field, 'read');
    return (undef) unless defined($self->_Value($field));
    my $f = str_to_dm($self->_Value($field));
    return (undef) unless $f; 
    return $f->calc($base, 1);
}

sub RT::Ticket::get_datemanip_worktime
{
    my $self = shift;
    
    return (undef) if $self->_Value('Due') eq NOT_SET;
    
    my $conf = load_config();
    my $eset = $self->FirstCustomFieldValue($conf->{'EscalationSetField'});
    return (undef) unless $eset;
    
    my @date_keys = keys %{$conf->{'EscalationSets'}->{$eset}->{_due}}
        if (exists($conf->{'EscalationSets'}->{$eset}) && exists($conf->{'EscalationSets'}->{$eset}->{_due}));
    return (undef) unless @date_keys;
    return (undef) if ( ! $self->_Value($date_keys[0]) || $self->_Value($date_keys[0]) eq NOT_SET );

    # (Due-startdate)-NOW
    my $due_date = $self->get_datemanip_date('Due');
    return (undef) unless $due_date;
    my $start_date = $self->get_datemanip_date($date_keys[0]);
    my $due_start_delta = $due_date->calc($start_date, 1);
    
    return $due_start_delta->calc($self->get_datemanip_delta('Due'), 1);
}

1;