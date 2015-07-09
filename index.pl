#!/usr/bin/perl

# Safe Typeing:
use warnings;

# Our DB Module:
use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=navua.db");

# Our YAML Parsing + HTML Templating Engine:
use HTML::Template;
use YAML::XS 'LoadFile';

# Load our YAML:
my $config = LoadFile('config.yaml');

# CGI Module:
use CGI;
my $q = CGI->new();

# Extract our dates:
my $date = `date "+%F"`;
( my $year ) = $date =~ /([0-9]{4})-[0-9]{2}-[0-9]{2}/; 
( my $month ) = $date =~ /[0-9]{4}-([0-9]{2})-[0-9]{2}/; 
( my $day ) = $date =~ /[0-9]{4}-[0-9]{2}-([0-9]{2})/; 

# If we were POSTed; lets update our db:
if ( $q->request_method eq "POST" ) {
	my $inputPay = $q->param("inputPay");
	my $query = "INSERT INTO payments(date,amount) VALUES ('$date',$inputPay)";
	my $returnVal = $dbh->do($query) or die $DBI::errstr;
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

# Calculate our months since we started this whole mortagage payment thing:
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

# Output:
print "Content-Type: text/html\n\n", $head_template->output, $template->output, $tail_template->output;
