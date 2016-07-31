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

# Extract our dates:
my $dateHash = {};
$dateHash->{fullDate} = `date "+%F"`;
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

sub getRollingHistory {

	my $historyDepth = 6;
	my $navuaAO = shift;
	my $avref = shift;
	my $rollingHistory;
	my $i = 0;
	
	while ( $i < $historyDepth ) {
		my $history = {};
		
		#Calculate Start:
		$history->{cycDay} = $dateHash->{cycDay};
		$history->{cycYear} = $dateHash->{cycYear};
		$history->{cycMonth} = sprintf("%02d", $dateHash->{cycMonth} - ($historyDepth - $i - 1)); 
		if ( $history->{cycMonth} < 1 ) {
			$history->{cycMonth} = 12;
                        $history->{cycYear} = sprintf("%02d", $dateHash->{calYear} - 1);
		}
		
		#Calculate End:
		$history->{cycDayEnd} = 14;
		$history->{cycYearEnd} = $dateHash->{cycYear};
		$history->{cycMonthEnd} = sprintf("%02d", $history->{cycMonth} + 1);
		# Roll over:
		if ( $history->{cycMonthEnd} > 12 ) {
			$history->{cycMonthEnd} = sprintf("%02d", 1);
			$history->{cycYearEnd} = sprintf("%02d", $history->{cycYear} + 1);
		}

		$history->{cycStart} = "$history->{cycYear}" . "-" . "$history->{cycMonth}" . "-" . "$history->{cycDay}";
		$history->{cycEnd} = "$history->{cycYearEnd}" . "-" . "$history->{cycMonthEnd}" . "-" . "$history->{cycDayEnd}";
		$history->{monthName} = $numMonth{"$history->{cycMonth}"};
		$history->{sum} = $navuaAO->getOffsetPaidCycle("$history->{cycStart}", "$history->{cycEnd}");
		$$avref = $$avref + $history->{sum};

		unshift(@$rollingHistory, $history);
		$i++;
	}

	$$avref = sprintf("%02d", ( $$avref / $historyDepth ));

	return $rollingHistory;
}

sub Main {

        # Define our Template Objects:
        my $head_template = HTML::Template->new( filename => "newhead.tmpl" );
        my $template = HTML::Template->new( filename => "newindex.tmpl", die_on_bad_params => 0 );
        my $tail_template = HTML::Template->new( filename => "newtail.tmpl" );

	getCurrentPayCycle();

	my $navuaAO = NavuaAO->new(filename => "navua.db");

	my $average = 0;
	my $lifeAverage = 0;

	$template->param( lastOffsetValue, $navuaAO->getLastOffsetValue() );
	$template->param( mortgageRemaining, $navuaAO->getMortgageRemainingPretty($config->{totalMortgage}) );
	$template->param( currentOffset, $navuaAO->getCurrentOffset($config->{payDay}) );
	$template->param( payCycleStart, $dateHash->{cycStart} );
	$template->param( payCycleEnd, $dateHash->{cycEnd} );
	$template->param( currentOffsetPayment, $navuaAO->getOffsetPaidCycle("$dateHash->{cycStart}", "$dateHash->{cycEnd}") );
	$template->param( rollingHistory, getRollingHistory($navuaAO, \$average) );
	$template->param( averagePayment, $average);

        # Output:
        print "Content-Type: text/html\n\n", $head_template->output, $template->output, $tail_template->output;
}

Main();
