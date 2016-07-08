#!/usr/bin/perl

# Safe Typeing:
use warnings;

## Global Config ##

# Our DB Module:
use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=navua.db");

# Our YAML Parsing + HTML Templating Engine:
use HTML::Template;
use YAML::XS 'LoadFile';

# Load our YAML config (public + secret):
my $config = LoadFile('config.yaml');
my $secret_config = LoadFile('secret.yaml');

# CGI Module:
use CGI;
my $q = CGI->new();

# Extract our dates:
my $date = `date "+%F"`;
( my $year ) = $date =~ /([0-9]{4})-[0-9]{2}-[0-9]{2}/; 
( my $month ) = $date =~ /[0-9]{4}-([0-9]{2})-[0-9]{2}/; 
( my $day ) = $date =~ /[0-9]{4}-[0-9]{2}-([0-9]{2})/; 

# Generate our logical dates:
my ( $lday, $lmonth, $lyear ) = ( $day, $month, $year );
my $logicalMonthMode = 1;
generateLogicalDates();

#print "$lmonth\n";
#exit 1;

# Convert Numerical Values to Text Value for Month:
my %numMonth = qw(
  01 Jan  02 Feb  03 Mar  04 Apr  05 May  06 Jun
  07 Jul  08 Aug  09 Sep  10 Oct  11 Nov  12 Dec
);

## End Global ##

# Notify parties that an amount has been payed on the mortgage:
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

# Calculate the amount of Offset paid till date:
sub calculateOffset {

	# Prepare our query:
	my $query = "SELECT SUM(amount) FROM payments";
	my $sqlQuery = $dbh->prepare("$query");
	$sqlQuery->execute();

	# Do the maths:
	my $offsetAmount = $sqlQuery->fetchrow();
	my $mortgageRemaining = $config->{"totalMortgage"} - $offsetAmount;

	return ( $offsetAmount, $mortgageRemaining );
}

# Calculate current month of mortgage:
sub calculateDuration {

	# Calculate our months since we started this whole mortgage payment thing:
	( my $startYear ) = $config->{"startDate"} =~ /([0-9]{4})-[0-9]{2}-[0-9]{2}/; 
	( my $startMonth ) = $config->{"startDate"} =~ /[0-9]{4}-([0-9]{2})-[0-9]{2}/; 

	my $diffYears = $lyear - $startYear;
	my $diffMonths = $lmonth - $startMonth;
	my $monthsPassed = ( $diffYears * 12 ) + $diffMonths;

	return ( $startYear, $startMonth, $monthsPassed );
}

# Generate our Logical Dates, if logicalMonthMode == 1
# This aligns our dates with our PayDate/YAML defined pay cycle:
sub generateLogicalDates {
	if ( $logicalMonthMode == 1 ) {
		if ( $day < $config->{"payDay"} ) {
			$lmonth = sprintf("%02d", $lmonth - 1);
			# Wrap around to the previous year if nessesary:
			if ( $lmonth < 1 ) {
				$lmonth = "12";
				$lyear = $lyear - 1;
			}
		}
	}
}

# Calculate the amount to date that we have payed this month:
sub amountPayedThisMonth {

	# Calculate the amount payed this month:

	#my $query = "SELECT SUM(amount) FROM payments WHERE date LIKE '%$lyear-$lmonth%'";
	my $cutoffDay = $config->{payDay} - 1;
	my $query = "SELECT SUM(amount) FROM payments WHERE date BETWEEN '$lyear-$lmonth-$config->{payday}' AND '$year-$month-$cutoffDay'";
	my $sqlQuery = $dbh->prepare("$query");
	$sqlQuery->execute();

	my $payedThisMonth = $sqlQuery->fetchrow();
	if ( ! defined $payedThisMonth ) {
		$payedThisMonth = "0.00";
	}

	return $payedThisMonth;
}

# Add a payment into the offset / against the mortgage:
sub addPayment {

	chomp($date);
	my $inputPay = $q->param("inputPay");
	my $query = "INSERT INTO payments(date,amount) VALUES ('$date',$inputPay)";
	my $returnVal = $dbh->do($query) or die $DBI::errstr;
	notifyPayment("$inputPay");
}

# Check to see if it's passed payday and a payment has not been made a.k.a payment needed :) :
sub checkPaymentNeeded {

	# Check to see if we've been naughty:
	my $paymentNeeded = 1;

	# If it's past our payDay cutoff:
	if ( $day >= $config->{"payDay"} ) {

		# Prepare our SQL Query:
		my $sqlQuery = $dbh->prepare("SELECT date FROM payments");
		$sqlQuery->execute();

		# If we have payed for this month, we dont need to pay again silly:
		while ( my $row = $sqlQuery->fetchrow_hashref ) {
			if ( $row->{"date"} =~ /$year-$month/ ) {
				$paymentNeeded = 0;
			}
		}

	# Its still early in the month, we dont need to pay up just yet:
	} else {
		$paymentNeeded = 0;
	}

	return $paymentNeeded;
}

# Generate our last X month history of "donations":
sub generateRollingHistory {

	my $offsetAmount = shift;
	my $monthsPassed = shift;

	my @rollingHistory;
	my $historyLimit = 6;
	my $average = 0;

	my $sqlQuery = $dbh->prepare("SELECT substr(date,6,2) AS paymonth, SUM(amount) AS paysum 
				      FROM payments GROUP BY substr(date,0,8) ORDER BY date DESC LIMIT $historyLimit");
	$sqlQuery->execute();

	while ( my $row = $sqlQuery->fetchrow_hashref ) {
		if ( $numMonth{"$row->{paymonth}"} =~ $numMonth{"$lmonth"} ) {
			$row->{paymonth} = $numMonth{"$row->{paymonth}"} . " <i>(Current)</i>";
		} else {
			$row->{paymonth} = $numMonth{"$row->{paymonth}"};
		}
		$average = $average + $row->{"paysum"};
		#$row->{"paysum"} = formatNumbers($row->{"paysum"});
		$row->{"paysum"} = getSignedValue($row->{"paysum"});
		push(@rollingHistory, $row);
	}

	# Calculate Average Donation and Slam into an anonymous hash:
	$average = $average / $historyLimit;
	$average =~ s/\.[0-9]*//g;
	unshift(@rollingHistory, { paymonth => "<b>6 Mo. Average:</b>", paysum => getSignedValue($average) });

	# Calculate our total average payment for the current life of the loan:
	my $totalAverage = $offsetAmount / $monthsPassed;
	$totalAverage =~ s/\.[0-9]*//g;
	unshift(@rollingHistory, { paymonth => "<b>Life Average:</b>", paysum => getSignedValue($totalAverage) });

	return \@rollingHistory;
}

# Check if interest is due:
sub checkInterestDue {

	my $interest_due = 0;
	$interest_due = 1 if $day >= $config->{payDay};
	return $interest_due;
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

# Sub to return correct signed dollar value
# Not originally written in, but since life happens, sometimes you gotta go with flow:
sub getSignedValue {

	my $val = shift;
	if ( $val >= 0 ) {
		return "+ \$" . abs($val);
	} else {
		return "- \$" . abs($val);
	}
}

sub Main{

	# If we were POSTed; lets update our db:
	if ( $q->request_method eq "POST" ) {
		addPayment();
	}

	# Define our Template Objects:
	my $head_template = HTML::Template->new( filename => "head.tmpl" );
	my $template = HTML::Template->new( filename => "index.tmpl", die_on_bad_params => 0 );
	my $tail_template = HTML::Template->new( filename => "tail.tmpl" );

	# Fill out and fire away:
	my ( $offsetAmount, $mortgageRemaining ) = calculateOffset();
	my ( $startYear, $startMonth, $monthsPassed ) = calculateDuration();
	my $paymentNeeded = checkPaymentNeeded();

	$template->param( month, $monthsPassed );
	$template->param( paymentNeeded, $paymentNeeded );
	$template->param( offsetAmount, formatNumbers($offsetAmount) );
	$template->param( mortgageRemaining, formatNumbers($mortgageRemaining) );
	$template->param( payedThisMonth, getSignedValue(amountPayedThisMonth()) );
	$template->param( rollingHistory, generateRollingHistory($offsetAmount, $monthsPassed) );
	$template->param( interestDue, checkInterestDue() );
	$template->param( generateEmail, $ENV{GEN_EMAIL} );

	# Output:
	print "Content-Type: text/html\n\n", $head_template->output, $template->output, $tail_template->output;
}

Main();
