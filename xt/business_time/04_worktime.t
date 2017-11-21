use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef;
require RT::Extension::EscalationSets::MockTransaction;
use RT::Extension::EscalationSets::TestFunc;

use RT::Extension::EscalationSets
    qw/ str_to_dm  load_config /;
use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

use constant DATE_FORMAT => '%Y-%m-%d %T';
use constant NOT_SET => '1970-01-01 00:00:00';

# Date::Manip objects
my $now = str_to_dm(Val => 'now', ToTz => 'UTC');
my $not_set = str_to_dm(Val => NOT_SET, FromTz => 'UTC');
my $dm_config = {
    WorkDayBeg => '08:00:00',
    WorkDayEnd => '17:00:00'
};
my $now_business = str_to_dm(Val => 'now', ToTz => 'UTC', Config => $dm_config);

my $ac = new RT::Action::EscalationSets;

my ( $baseurl, $m ) = RT::Test->started_ok();

subtest 'now before started' => sub {
    my $ticket = new_ticket();
    $ticket->SetStarts(increase_date($now, '5 minutes')->printf(DATE_FORMAT));
    my $check = $now->calc(increase_date($now, '-5 minutes'), 0)->value();

    my $res = RT::Extension::EscalationSets::get_worktime_delta(
        $ticket,
        str_to_dm(Val => $ticket->Starts, FromTz => 'UTC'),
        $now,
        undef
    );

    isnt($res, undef, 'return not undef');
    cmp_ok( $res->value(), 'eq', $check);
};

subtest 'now on started' => sub {
    my $ticket = new_ticket();
    $ticket->SetStarts($now->printf(DATE_FORMAT));
    my $check = $now->calc($now, 1)->value(); # Possible move to business day

    my $res = RT::Extension::EscalationSets::get_worktime_delta(
        $ticket,
        str_to_dm(Val => $ticket->Starts, FromTz => 'UTC'),
        $now,
        $dm_config
    );

    isnt($res, undef, 'return not undef');
    cmp_ok( $res->value(), 'eq', $check);
};

subtest 'now just after started' => sub {
    my $ticket = new_ticket();
    $ticket->SetStarts(increase_date($now, '-5 minutes')->printf(DATE_FORMAT));
    my $check = $now->calc(increase_date($now, '5 minutes'), 0)->value();

    my $res = RT::Extension::EscalationSets::get_worktime_delta(
        $ticket,
        str_to_dm(Val => $ticket->Starts, FromTz => 'UTC'),
        $now,
        $dm_config
    );

    isnt($res, undef, 'return not undef');
    cmp_ok( $res->value(), 'eq', $check);
};

subtest 'now just after started, Due was set before Starts' => sub {
    my $ticket = new_ticket();
    my $txn = do_set_unset_due($ticket, increase_date($now, '30 minutes')->printf(DATE_FORMAT));
    sleep 3;
    my $now2 = str_to_dm(Val => 'now', ToTz => 'UTC');
    $ticket->SetStarts($now2->printf(DATE_FORMAT));
    my $check = $now2->calc(increase_date($now2, '5 minutes'), 0)->value();

    my $res = RT::Extension::EscalationSets::get_worktime_delta(
        $ticket,
        str_to_dm(Val => $ticket->Starts, FromTz => 'UTC'),
        increase_date($now2, '5minutes'),
        $dm_config
    );

    isnt($res, undef, 'return not undef');
    cmp_ok( $res->value(), 'eq', $check);
};

subtest 'SLA was paused, now is out of SLA' => sub {
    my $ticket = new_ticket();
    $ticket->SetStarts(increase_date($now, '-15 minutes')->printf(DATE_FORMAT));
    my $txn = do_set_unset_due($ticket, increase_date($now, '30 minutes')->printf(DATE_FORMAT));
    my $txncreatedobj = str_to_dm(Val => $txn->Created, FromTz => 'UTC');
    sleep 2;
    my $check = $txncreatedobj->calc(increase_date($now, '-15 minutes'), 1)->value();
    my $now2 = str_to_dm(Val => 'now', ToTz => 'UTC');

    my $res = RT::Extension::EscalationSets::get_worktime_delta(
        $ticket,
        str_to_dm(Val => $ticket->Starts, FromTz => 'UTC'),
        $now2,
        $dm_config
    );

    isnt($res, undef, 'return not undef');
    cmp_ok( $res->value(), 'eq', $check);
};

subtest 'SLA was paused, now is in SLA' => sub {
    my $ticket = new_ticket();
    $ticket->SetStarts(increase_date($now, '-15 minutes')->printf(DATE_FORMAT));
    my $txn = do_set_unset_due($ticket, increase_date($now, '30 minutes')->printf(DATE_FORMAT));
    my $txncreatedobj = str_to_dm(Val => $txn->Created, FromTz => 'UTC');

    #txn Created must be in past
    sleep 3;
    $ticket->SetDue(increase_date($now, '30 minutes')->printf(DATE_FORMAT));
    my $txn2createdobj = str_to_dm(Val => $ticket->Transactions->Last->Created, FromTz => 'UTC');

    #txn Created also must be in past
    sleep 2;
    my $now2 = str_to_dm(Val => 'now', ToTz => 'UTC');
    my $check = $now2->calc(increase_date($now, '-15 minutes'), 1);
    $check = $check->calc($txn2createdobj->calc($txncreatedobj, 1), 1);
    $check = $check->value();

    my $res = RT::Extension::EscalationSets::get_worktime_delta(
        $ticket,
        str_to_dm(Val => $ticket->Starts, FromTz => 'UTC'),
        $now2,
        $dm_config
    );

    isnt($res, undef, 'return not undef');
    cmp_ok( $res->value(), 'eq', $check);
};

undef $m;

done_testing();