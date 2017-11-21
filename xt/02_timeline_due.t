use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef;
require RT::Extension::EscalationSets::MockTransaction;
use RT::Extension::EscalationSets::TestFunc;

use RT::Extension::EscalationSets;
use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

use constant DATE_FORMAT => '%Y-%m-%d %T';
use constant NOT_SET => '1970-01-01 00:00:00';

# Date::Manip objects
my $now = str_to_dm(Val => 'now', ToTz => 'UTC');
my $not_set = str_to_dm(Val => NOT_SET, FromTz => 'UTC');

my $ac = new RT::Action::EscalationSets;

my ( $baseurl, $m ) = RT::Test->started_ok();

subtest 'Config delta is unset' => sub {
    my $ticket = new_ticket();
    my $check = increase_date($now, '10 minutes');
    $ticket->SetDue($check->printf(DATE_FORMAT));
    my $txn = undef;
    
    my $res = $ac->timeline_due(undef, undef, $txn, $now, $ticket);
    is($res, undef, 'return undef');
};

subtest 'Referred date is undef' => sub {
    my $ticket = new_ticket();
    my $check = undef;
    my $txn = undef;
    
    my $res = $ac->timeline_due(['Told', '-3 minutes'], undef, $txn, $now, $ticket);
    is($res, undef, 'return undef');
};

subtest 'Referred date is 1970-01-01 00:00:00' => sub {
    my $ticket = new_ticket();
    $ticket->SetStarts(NOT_SET);
    my $check = undef;
    my $txn = undef;
    
    my $res = $ac->timeline_due(['Starts', '-3 minutes'], undef, $txn, $now, $ticket);
    is($res, undef, 'return undef');
};

subtest 'Due was unset, Ticket was before Due' => sub {
    my $ticket = new_ticket();
    my $oldtxnval = increase_date($now, '10 minutes');
    my $txncreated = increase_date($now, '-20 minutes');
    my $check = increase_date($now, '30minutes');
    # On txn creation moment Due was a 30 minutes in the future
    my $txn = do_set_unset_due($ticket, $oldtxnval->printf(DATE_FORMAT));
    $txn->SetCreated($txncreated->printf(DATE_FORMAT));
    
    my $res = $ac->timeline_due(['Created', '5 minutes'], undef, $txn, $now, $ticket);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return NOW+(txn_val-txn_created)');
};

subtest 'Due was unset, Ticket was Overdue' => sub {
    my $ticket = new_ticket();
    my $oldtxnval = increase_date($now, '-30 minutes');
    my $txncreated = increase_date($now, '-20 minutes');
    # On txn creation moment Due was a 10 minutes in the past
    my $txn = do_set_unset_due($ticket, $oldtxnval->printf(DATE_FORMAT));
    $txn->SetCreated($txncreated->printf(DATE_FORMAT));
    
    my $res = $ac->timeline_due(['Created', '5 minutes'], undef, $txn, $now, $ticket);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $oldtxnval->printf(DATE_FORMAT), 'return txn_val');
};

subtest 'Due was not unset' => sub {
    my $ticket = new_ticket();
    my $created = new Date::Manip::Date;
    $created->parse($ticket->Created); # UTC
    my $check = increase_date($created, '5 minutes');
    my $txn = undef;
    
    my $res = $ac->timeline_due(['Created', '5 minutes'], undef, $txn, $now, $ticket);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return ticket_created+config_due');
};

undef $m;
done_testing();