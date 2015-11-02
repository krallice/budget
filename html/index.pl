#!/usr/bin/perl

# Safe Typeing:
use warnings;

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

# Calculate the amount to date that we have payed this month:
sub amountPayedThisMonth {

	# Calculate the amount payed this month:
	my $query = "SELECT SUM(amount) FROM payments WHERE date LIKE '%$year-$month%'";
	my $sqlQuery = $dbh->prepare("$query");
	$sqlQuery->execute();

	my $payedThisMonth = $sqlQuery->fetchrow();
	if ( ! defined $payedThisMonth ) {
		$payedThisMonth = "0.00";
	}

	return $payedThisMonth;
}

sub Main{

	# If we were POSTed; lets update our db:
	if ( $q->request_method eq "POST" ) {
		chomp($date);
		my $inputPay = $q->param("inputPay");
		my $query = "INSERT INTO payments(date,amount) VALUES ('$date',$inputPay)";
		my $returnVal = $dbh->do($query) or die $DBI::errstr;
		notifyPayment("$inputPay");
	}

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

	# Define our Template Objects:
	my $head_template = HTML::Template->new( filename => "head.tmpl" );
	my $template = HTML::Template->new( filename => "index.tmpl", die_on_bad_params => 0 );
	my $tail_template = HTML::Template->new( filename => "tail.tmpl" );

	# Prepare our query:
	$query = "SELECT SUM(amount) FROM payments";
	$sqlQuery = $dbh->prepare("$query");
	$sqlQuery->execute();

	# Do the maths:
	my $offsetAmount = $sqlQuery->fetchrow();
	my $mortgageRemaining = $config->{"totalMortgage"} - $offsetAmount;

	# Calculate our months since we started this whole mortgage payment thing:
	( my $startYear ) = $config->{"startDate"} =~ /([0-9]{4})-[0-9]{2}-[0-9]{2}/; 
	( my $startMonth ) = $config->{"startDate"} =~ /[0-9]{4}-([0-9]{2})-[0-9]{2}/; 

	my $diffYears = $year - $startYear;
	my $diffMonths = $month - $startMonth;
	my $monthsPassed = ( $diffYears * 12 ) + $diffMonths;

	# Fill out and fire away:
	$template->param( month, $monthsPassed );
	$template->param( paymentNeeded, $paymentNeeded );
	$template->param( offsetAmount, $offsetAmount );
	$template->param( mortgageRemaining, $mortgageRemaining );
	$template->param( payedThisMonth, amountPayedThisMonth );
	$template->param( generateEmail, $ENV{GEN_EMAIL} );

	# Output:
	print "Content-Type: text/html\n\n", $head_template->output, $template->output, $tail_template->output;
}

Main();
