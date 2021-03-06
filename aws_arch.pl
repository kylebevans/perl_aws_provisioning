#!/usr/bin/env perl

use local::lib;
use Paws;
use Data::Printer;


# read in the cloudformation template
my $file = "kbe.tpl";
my $cftemplate;
{
    local $/;
    open my $fh, '<', $file or die "can't open $file: $!";
    $cftemplate = <$fh>;
}

# assumes AWS credentials are stored in ~/.aws/credentials

my $ec2 = Paws->service('EC2', region => 'us-east-2') or die "can't create KeyPair: $!";

my $KeyPair = $ec2->CreateKeyPair(KeyName => 'kbe-key-pair-useast2');
print $KeyPair->KeyMaterial . "\n";



# create the stack in us-east-2
my $cfkbe = Paws->service('CloudFormation', region => 'us-east-2') or die "can't create CloudFormation object: $!";

@parameters = { ParameterKey => "KeyName", ParameterValue => "kbe-key-pair-useast2" };

$parameters_ref = \@parameters;

my $stackoutput = $cfkbe->CreateStack(
  Parameters => $parameters_ref,
  StackName => "kbestack",
  TemplateBody => $cftemplate
) or die "stack creation failed: $!";

my $stackid = $stackoutput->StackId;

# Show stack events during stack creation process.
# Stack creation is asynchronous, so you have to keep running
# DescribeStackEvents to keep getting the events until the stack creation
# is complete or the rollback is complete in the event of failure.
# However, that also means you get the old events again, so this keeps
# a hash of all the events gotten over time and doesn't print duplicates.
# DescribeEvents is also paginated, so you have to get the first page, process it,
# then loop through all of the other pages if they exist and process them.
my @eventlist;
while (!(grep(/CREATE_COMPLETE AWS::CloudFormation::Stack.+/, @eventlist)) && !(grep(/DELETE_COMPLETE AWS::CloudFormation::Stack.+/, @eventlist)) && !(grep(/ROLLBACK_COMPLETE AWS::CloudFormation::Stack.+/, @eventlist))) {
  # process first page of events
  my $stackeventsoutput = $cfkbe->DescribeStackEvents(StackName => $stackid) or die "describe stack events failed: $!";
  @stackeventlists = $stackeventsoutput->StackEvents;
  foreach $stackeventlist (@stackeventlists) {
    while ($stackevent = pop(@$stackeventlist)) {
      $rstatus = $stackevent->ResourceStatus;
      $rstatusreason = $stackevent->ResourceStatusReason;
      $rtype = $stackevent->ResourceType;
      $lrid = $stackevent->LogicalResourceId;
      $eventlistmember = $rstatus . " " . $rtype . " " . $lrid . " " . $rstatusreason;
      if (!(grep($eventlistmember eq $_, @eventlist))) {
        push @eventlist, $eventlistmember;
        print $eventlistmember . "\n";
      }
    }
  }
  # process the rest of the pages of events if they exist
  while ($stackeventsoutput->NextToken) {
    $stackeventsoutput = $cfkbe->DescribeStackEvents(StackName => $stackid, NextToken => $stackevents->NextToken) or die "describe stack events failed: $!";
    @stackeventlists = $stackeventsoutput->StackEvents;
    foreach $stackeventlist (@stackeventlists) {
      while ($stackevent = pop(@$stackeventlist)) {
        $rstatus = $stackevent->ResourceStatus;
        $rstatusreason = $stackevent->ResourceStatusReason;
        $rtype = $stackevent->ResourceType;
        $lrid = $stackevent->LogicalResourceId;
        $eventlistmember = $rstatus . " " . $rtype . " " . $lrid . " " . $rstatusreason;
        if (!(grep($eventlistmember eq $_, @eventlist))) {
          push @eventlist, $eventlistmember;
          print $eventlistmember . "\n";
        }
      }
    }
  }
}

# print the URL of the site
my $describestacksoutput = $cfkbe->DescribeStacks(StackName => $stackid) or die "describe stacks failed: $!";
@stacks = $describestacksoutput->Stacks;
$kbestack = pop($stacks[0]);
@kbestackoutputs = $kbestack->Outputs;
p @kbestackoutputs;

