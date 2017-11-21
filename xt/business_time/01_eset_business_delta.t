use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef;
require RT::Extension::EscalationSets::MockTransaction;
use RT::Extension::EscalationSets qw/str_to_dm/;
use RT::Extension::EscalationSets::TestFunc;

use constant DATE_FORMAT => '%Y-%m-%d %T';

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

# Date::Manip objects
my $now = str_to_dm(Val => 'now', ToTz => 'UTC');
my $dm_config = {
    WorkDayBeg => '08:00:00',
    WorkDayEnd => '17:00:00'
};
my $now_business = str_to_dm(Val => 'now', ToTz => 'UTC', Config => $dm_config);
my $not_set = str_to_dm(Val => NOT_SET, FromTz => 'UTC');
my @dates_test_set = (
    # start_date           # old_due              # check new_due
    '2016-05-13 07:30:00', '2016-05-13 08:30:00', '2016-05-13 11:00:00',
    '2016-05-12 16:30:00', '2016-05-12 17:30:00', '2016-05-13 10:30:00',
    '2016-05-12 20:00:00', '2016-05-12 21:00:00', '2016-05-13 11:00:00',
    '2016-05-12 14:30:00', '2016-05-12 15:30:00', '2016-05-13 08:30:00',
    '2016-05-12 13:30:00', '2016-05-12 14:30:00', '2016-05-12 16:30:00',
    '2016-05-12 17:30:00', '2016-05-13 09:00:00', '2016-05-13 12:00:00',
);

my $ac = new RT::Action::EscalationSets;

my ( $baseurl, $m ) = RT::Test->started_ok();


subtest 'eset_business_delta, NotBusinessSet -> BusinessSet' => sub {
    my $ticket = new_ticket();

    my @src = @dates_test_set;
    my $i = 1;
    while (@src) {
        $ticket->SetStarts(shift @src);
        # my $starts = str_to_dm(Val => $ticket->Starts, FromTz => 'UTC', Config => $dm_config);
        my $old_due = str_to_dm(Val => shift @src, FromTz => 'UTC', Config => $dm_config);
        my $res = $ac->esets_business_delta(
            ['Starts', '1 hour'],
            ['Starts', '3 business hour'],
            $dm_config,
            $ticket
        );
        cmp_ok(
            $old_due->calc($res, 0)->printf(DATE_FORMAT),
            'eq',
            shift @src,
            "data set $i"
        );
        $i++;
    }
};

subtest 'eset_change_due, NotBusinessSet -> BusinessSet' => sub {
    my $ticket = new_ticket();

    my @src = @dates_test_set;
    my $i = 1;
    while (@src) {
        $ticket->SetStarts(shift @src);
        my $starts = str_to_dm(Val => $ticket->Starts, FromTz => 'UTC', Config => $dm_config);
        my $old_due = str_to_dm(Val => shift @src, FromTz => 'UTC');
        my $res = $ac->eset_change_due(
            $old_due,
            ['Starts', '1 hour'],
            ['Starts', '3 business hour'],
            $dm_config,
            $ticket
        );
        cmp_ok(
            $res->printf(DATE_FORMAT),
            'eq',
            shift @src,
            "data set $i"
        );
        $i++;
    }
};

undef $m;

done_testing();