#!/usr/bin/perl

use strict;
no strict "subs";
use warnings;

use NavuaAO;
use CGI;
use HTML::Template;
use YAML::XS 'LoadFile';

# Load our YAML config (public + secret):
my $config = LoadFile('config.yaml');
my $secret_config = LoadFile('secret.yaml');

# Init CGI Module:
my $q = CGI->new();

# Extract our dates:
my $dateHash = {};
$dateHash->{fullDate} = `date "+%F"`;
chomp($dateHash->{fullDate});
( $dateHash->{calYear} ) = $dateHash->{fullDate} =~ /([0-9]{4})-[0-9]{2}-[0-9]{2}/;
( $dateHash->{calMonth} ) = $dateHash->{fullDate} =~ /[0-9]{4}-([0-9]{2})-[0-9]{2}/;
( $dateHash->{calDay} ) = $dateHash->{fullDate} =~ /[0-9]{4}-[0-9]{2}-([0-9]{2})/;

my %numMonth = qw(
  01 Jan  02 Feb  03 Mar  04 Apr  05 May  06 Jun
  07 Jul  08 Aug  09 Sep  10 Oct  11 Nov  12 Dec
);

sub getCurrentPayCycle {

	# Calculate our start of cycle:
	$dateHash->{cycDay} = 15;
	$dateHash->{cycMonth} = $dateHash->{calMonth};
	$dateHash->{cycYear} = $dateHash->{calYear};

	if ( $dateHash->{calDay} < $config->{payDay} ) {
		$dateHash->{cycMonth} = sprintf("%02d", $dateHash->{calMonth} - 1);
		if ( $dateHash->{cycMonth} < 1 ) {
			$dateHash->{cycMonth} = 12;
			$dateHash->{cycYear} = sprintf("%02d", $dateHash->{calYear} - 1);
		}
	}
	$dateHash->{cycStart} = "$dateHash->{cycYear}" . "-" . "$dateHash->{cycMonth}" . "-" . "$dateHash->{cycDay}";

	# Calculate our end of cycle:
	$dateHash->{cycDayEnd} = 14;
	$dateHash->{cycYearEnd} = $dateHash->{cycYear};
	$dateHash->{cycMonthEnd} = sprintf("%02d", $dateHash->{cycMonth} + 1);
	# Roll over:
	if ( $dateHash->{cycMonthEnd} > 12 ) {
		$dateHash->{cycMonthEnd} = sprintf("%02d", 1);
		$dateHash->{cycYearEnd} = sprintf("%02d", $dateHash->{cycYear} + 1);
	}
	$dateHash->{cycEnd} = "$dateHash->{cycYearEnd}" . "-" . "$dateHash->{cycMonthEnd}" . "-" . "$dateHash->{cycDayEnd}";
}

sub calculateDuration {

	# Calculate our months since we started this whole mortgage payment thing:
	( my $startYear ) = $config->{"startDate"} =~ /([0-9]{4})-[0-9]{2}-[0-9]{2}/; 
	( my $startMonth ) = $config->{"startDate"} =~ /[0-9]{4}-([0-9]{2})-[0-9]{2}/; 

	my $diffYears = $dateHash->{cycYear} - $startYear;
	my $diffMonths = $dateHash->{cycMonth} - $startMonth;
	my $monthsPassed = ( $diffYears * 12 ) + $diffMonths;

	#return ( $startYear, $startMonth, $monthsPassed );
	return $monthsPassed
}

sub getRollingHistory {

	my $historyDepth = 6;
	my $navuaAO = shift;
	my $avref = shift;
	my $liferef = shift;
	my $monthsPassed = shift;
	my $rollingHistory;
	my $i = 0;
	
	while ( $i < $historyDepth ) {
		my $history = {};
		
		# Calculate Start:
		$history->{cycDay} = $dateHash->{cycDay};
		$history->{cycYear} = $dateHash->{cycYear};
			
		if ( checkPaymentNeeded($navuaAO) == 0 ) {
			$history->{cycMonth} = sprintf("%02d", $dateHash->{cycMonth} - ($historyDepth - $i - 1)); 
		# We have to make a payment, so do not include this month + lets go back one more:
		} else {
			$history->{cycMonth} = sprintf("%02d", $dateHash->{cycMonth} - ($historyDepth - $i));
		}

		# Roll over behind December:
		if ( $history->{cycMonth} < 1 ) {
			$history->{cycMonth} = sprintf("%02d", 12 + $history->{cycMonth});
                        $history->{cycYear} = sprintf("%02d", $dateHash->{calYear} - 1);
			$history->{cycYearEnd} = sprintf("%02d", $dateHash->{cycYear} - 1);
			
		# Else we're still in the current year:
		} else {
			$history->{cycYearEnd} = sprintf("%02d", $dateHash->{cycYear});
		}

		# Calculate our end periods:
		$history->{cycDayEnd} = 14;
		$history->{cycMonthEnd} = sprintf("%02d", $history->{cycMonth} + 1);

		# Prepare for our NavuaAO getOffsetPaidCycle() query:
		$history->{cycStart} = "$history->{cycYear}" . "-" . "$history->{cycMonth}" . "-" . "$history->{cycDay}";
		$history->{cycEnd} = "$history->{cycYearEnd}" . "-" . "$history->{cycMonthEnd}" . "-" . "$history->{cycDayEnd}";

		# Format our month names:
		if ( $history->{cycMonth} eq $dateHash->{cycMonth} ) {
			$history->{monthName} = $numMonth{"$history->{cycMonth}"} . " (Current)";
			#$history->{monthName} = "$history->{cycMonth} - $history->{cycMonthEnd} -- $history->{cycStart} to $history->{cycEnd}";
		} else {
			$history->{monthName} = $numMonth{"$history->{cycMonth}"};
			#$history->{monthName} = "$history->{cycMonth} - $history->{cycMonthEnd} -- $history->{cycStart} to $history->{cycEnd}";
		}

		# Fire off to our access object:
		$history->{sum} = $navuaAO->getOffsetPaidCycle("$history->{cycStart}", "$history->{cycEnd}");

		# Tally up average:
		$$avref = $$avref + $history->{sum};

		# Prepare/Sign our value, and unshift onto our retarray:
		$history->{sum} = getSignedValue($history->{sum});
		unshift(@$rollingHistory, $history);
		$i++;
	}

	# Manip our stats:
	$$avref = getSignedValue(sprintf("%02d", ( $$avref / $historyDepth )));
	$$liferef = getSignedValue($navuaAO->getLifeAverage($$monthsPassed));

	return $rollingHistory;
}

sub notifyPayment{

        # Check how much we've payed:
        my $inputPay = shift;

        # Generate our new HTML (after updating payed amount):
        my $htmlOutput = `REQUEST_METHOD="GET" GEN_EMAIL="YES" ./index.pl`;

        # Leverage Sendmail to send our notification email to respective parties:
        open  (SENDMAIL, "|/usr/sbin/sendmail -f '$config->{senderEmail}' -t");
        print SENDMAIL "From: $config->{senderEmail}\n";
        print SENDMAIL "To: $secret_config->{destinationEmails}\n";
        print SENDMAIL "MIME-Version: 1.0\n";
        print SENDMAIL "Subject: \$$inputPay Payed Off Mortgage!\n";
        print SENDMAIL "$htmlOutput";
        close (SENDMAIL);
}

sub checkPaymentNeeded {

	# Check to see if we've been naughty:
	my $navuaAO = shift;
	my $paymentNeeded = 0;

	# If it's past our payDay cutoff:
	if ( $dateHash->{calDay} >= $config->{"payDay"} ) {

		# Check if we've already made a payment:
		my $paymentMade = $navuaAO->checkPaymentsMade("$dateHash->{calYear}-$dateHash->{calMonth}");
		if ( $paymentMade == 0 ) {
			$paymentNeeded = 1;
		}
	# Its still early in the month, we dont need to pay up just yet:
	} else {
		$paymentNeeded = 0;
	}

	return $paymentNeeded;
}

sub getSignedValue {

	my $val = shift;
	if ( $val >= 0 ) {
		return "+ \$" . abs($val);
	} else {
		return "- \$" . abs($val);
	}
}

# Check if interest is due:
sub checkInterestDue {

	my $interest_due = 0;
	$interest_due = 1 if $dateHash->{calDay} >= $config->{payDay};
	return $interest_due;
}

sub checkRentDue {

	my $rent_due = 1;
	$rent_due = 0 if $dateHash->{calDay} >= $config->{rentDay} && $dateHash->{calDay} <= $config->{payDay};
	return $rent_due;
}

# Sub to format our numbers like XX,XXX etc..
sub formatNumbers {

	# Read our number reverse, and then split into an array:
	my $val = reverse shift;
	my @a = split("", $val);

	# Our return array:
	my @r;
	
	# If we have a complex number:
	if ( (scalar @a + 1) > 3) {

		# Iterate through the length:
		for my $i ( 0 .. $#a ) {
			if ( (($i + 1) % 3) == 0) {
				if ( $i != $#a ) {
					unshift(@r, "," . $a[$i]);
				} else {
					unshift(@r, $a[$i]);		
				}
			} else {
				unshift(@r, $a[$i]);		
			}
		}
	}
	
	# Flatten to scalar and return:
	return join("", @r);
}

sub Main {

        # Define our Template Objects:
        my $head_template = HTML::Template->new( filename => "head.tmpl" );
        my $template = HTML::Template->new( filename => "index.tmpl", die_on_bad_params => 0 );
        my $tail_template = HTML::Template->new( filename => "tail.tmpl" );

	getCurrentPayCycle();

	my $navuaAO = NavuaAO->new(filename => "navua.db");

	# If we were POSTed; lets update our db:
	if ( $q->request_method eq "POST" ) {
		if ( $q->param("inputPay") ) {
			$navuaAO->addOffsetPayment($dateHash->{fullDate},$q->param("inputPay"));
			#notifyPayment($q->param(inputPay));
		}
		if ( $q->param("inputSavings") ) {
			$navuaAO->addSavingsPayment($dateHash->{fullDate},$q->param("inputSavings"));
		}
	}

	my $average = 0;
	my $lifeAverage = 0;
	my $monthsPassed = calculateDuration();

	# Generate Interest/Rent Due Notifications:
	$template->param( interestDue, checkInterestDue() );
	$template->param( rentDue, checkRentDue() );

	# Base Stats:
	$template->param( lastOffsetValue, formatNumbers($navuaAO->getLastOffsetValue()) );
	$template->param( monthsPassed, $monthsPassed );
	$template->param( mortgageRemaining, formatNumbers($navuaAO->getMortgageRemaining($config->{totalMortgage})) );

	# Get our large progress values:
	$template->param( currentOffset, formatNumbers($navuaAO->getCurrentOffset($config->{payDay})) );
	$template->param( currentOffsetIncludingSavings, formatNumbers($navuaAO->getCurrentOffsetIncludingSavings($config->{payDay})) );

	$template->param( currentSavings, formatNumbers($navuaAO->getCurrentSavings($config->{payDay})) );

	# Check if we've paid yet?:
	$template->param( paymentNeeded, checkPaymentNeeded($navuaAO) );

	# Debugs:
	$template->param( payCycleStart, $dateHash->{cycStart} );
	$template->param( payCycleEnd, $dateHash->{cycEnd} );

	# Stats Table:
	$template->param( currentOffsetPayment, getSignedValue($navuaAO->getOffsetPaidCycle("$dateHash->{cycStart}", "$dateHash->{cycEnd}")) );

	# Generate our History Table:
	$template->param( rollingHistory, getRollingHistory($navuaAO, \$average, \$lifeAverage, \$monthsPassed) );
	$template->param( averagePayment, $average);
	$template->param( lifeAverage, $lifeAverage);

	$template->param( generateEmail, $ENV{GEN_EMAIL} );

	# Diags:
	#$template->param( diag_one, $navuaAO->checkPaymentsMade("$dateHash->{calYear}-$dateHash->{calMonth}") );
	#$template->param( diag_two, checkPaymentNeeded($navuaAO) );

        # Output:
        print "Content-Type: text/html\n\n", $head_template->output, $template->output, $tail_template->output;
}

Main();
