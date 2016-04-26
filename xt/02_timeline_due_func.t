use 5.010;
use strict;
use warnings;

use RT::Extension::EscalationSets::Test
    testing => 'RT::Action::EscalationSets',
    config => $ENV{RT_ADD_CONFIG} || '',
    tests => undef;
#use RT::Extension::EscalationSets::Test tests => undef, config=>'Set($DatabaseType, "Pg");', server_ok => 1;
require RT::Extension::EscalationSets::MockTransaction;

use constant DATE_FORMAT => '%Y-%m-%d %T';

## UNIX timestamp 0:
use constant NOT_SET => '1970-01-01 00:00:00';

use_ok('RT::Action::EscalationSets');
use_ok('Date::Manip::Date');

# Entries from Sample_SiteConfig.pm
my %escalation_sets_config = RT->Config->Get('EscalationSets');
my @test_esets = qw/RFI RFS/;
my @test_due = map{ $escalation_sets_config{$_}->{'_due'}->{'created'} } @test_esets;


my $ticket = undef;
my $txn = undef;

# Sets Due to value and unsets it again and returns the last (unset) txn
sub do_set_unset_due
{
    my ($tkt, $due) = @_; #due is string
    $tkt->SetDue($due);
    $tkt->SetDue(NOT_SET);
    return $tkt->Transactions->Last;
}

sub increase_date
{
	my $base_date = shift; #obj
	my $offset = shift; #string

	my $tdelta = $base_date->new_delta();
	$tdelta->parse($offset);
	return $base_date->calc($tdelta, 0);
}

sub new_ticket()
{
    return RT::Test->create_ticket(Queue => 'General', Content => 'Sample content', Subject => 'Sample ticket', Requestor => 'test@example.com');
}

my $ac = new RT::Action::EscalationSets;

# Now 
my $now = RT::Extension::EscalationSets::str_to_dm('now', '', 'UTC');

#Not set object
my $not_set = RT::Extension::EscalationSets::str_to_dm(NOT_SET, 'UTC');

my ( $baseurl, $m ) = RT::Test->started_ok();

subtest 'Config delta is unset' => sub {
    my $ticket = new_ticket();
    my $check = increase_date($now, '10 minutes');
    $ticket->SetDue($check->printf(DATE_FORMAT));
    my $txn = undef;
    
    my $res = $ac->timeline_due(undef, $ticket, $txn, $now);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return current Due' );
};

subtest 'Due set to something' => sub {
    my $ticket = new_ticket();
    my $check = increase_date($now, '10 minutes');
    $ticket->SetDue($check->printf(DATE_FORMAT));
    my $txn = undef;
    
    my $res = $ac->timeline_due($test_due[0], $ticket, $txn, $now);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return current Due' );
};

subtest 'Due was unset, Due was in future' => sub {
    my $ticket = new_ticket();
    my $oldtxnval = increase_date($now, '10 minutes');
    my $txncreated = increase_date($now, '-20 minutes');
    my $check = increase_date($now, '30minutes');
    # On txn creation moment Due was a 30 minutes in the future
    my $txn = do_set_unset_due($ticket, $oldtxnval->printf(DATE_FORMAT));
    $txn->SetCreated($txncreated->printf(DATE_FORMAT));
    
    my $res = $ac->timeline_due($test_due[0], $ticket, $txn, $now);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return NOW+(txn_val-txn_created)');
};

subtest 'Due was unset, Due was in past' => sub {
    my $ticket = new_ticket();
    my $oldtxnval = increase_date($now, '-30 minutes');
    my $txncreated = increase_date($now, '-20 minutes');
    # On txn creation moment Due was a 10 minutes in the past
    my $txn = do_set_unset_due($ticket, $oldtxnval->printf(DATE_FORMAT));
    $txn->SetCreated($txncreated->printf(DATE_FORMAT));
    
    my $res = $ac->timeline_due($test_due[0], $ticket, $txn, $now);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $oldtxnval->printf(DATE_FORMAT), 'return txn_val');
};

subtest 'Due was not unset, Due is unset now' => sub {
    my $ticket = new_ticket();
    my $created = new Date::Manip::Date;
    $created->parse($ticket->Created); # UTC
    my $check = increase_date($created, $test_due[0]);
    my $txn = undef;
    
    my $res = $ac->timeline_due($test_due[0], $ticket, $txn, $now);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $check->printf(DATE_FORMAT), 'return ticket_created+config_due');
};

subtest 'Due was unset, Due is set now to something' => sub {
    my $ticket = new_ticket();
    my $oldtxnval = increase_date($now, '-30 minutes');
    my $txncreated = increase_date($now, '-20 minutes');
    my $check = increase_date($now, '20 minutes');
    my $txn = do_set_unset_due($ticket, $oldtxnval->printf(DATE_FORMAT));
    $txn->SetCreated($txncreated->printf(DATE_FORMAT));
    $ticket->SetDue($check->printf(DATE_FORMAT));
    
    my $res = $ac->timeline_due($test_due[0], $ticket, $txn, $now);
    isnt($res, undef, 'return not undef');
    cmp_ok( $res->printf(DATE_FORMAT), 'eq', $ticket->Due, 'return ticket Due');
};


undef $m;
done_testing();