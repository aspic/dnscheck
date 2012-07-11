#!/usr/bin/perl
use warnings;
use strict;

package DNSCheckWeb::DB;

use Carp;
use Data::Dumper;

# Constants
use constant TYPE_PG => "postgresql";
use constant TYPE_MYSQL => "mysql";

my $dbo;

sub new {
	my ($class, $db_info) = @_;
	# Create empty object, will be filled.
	my $self = { };

	if(!defined($db_info)) {
		croak "No database information given";
	}

	# Initialize variables, should load database depending on what type.
	if($db_info->{type} eq TYPE_PG) {
		$self = {
			connect =>
			"DBI:Pg:database=%s;host=%s;port=%s",
			tbl_begin => "started",
			tbl_end => "finished",
			tbl_level => "degree"
		};
	} elsif($db_info->{type} eq TYPE_MYSQL) {
		$self = {
			connect =>
			"DBI:Pg:database=%s;host=%s;port=%s",
			tbl_begin => "started",
			tbl_end => "finished",
			tbl_level => "degree"
		};
	} else {
		croak "\'$db_info->{type}\' is not a known database type";
	}

	#Setup actual connection
	my $dsn  = sprintf($self->{connect}, $db_info->{database}, $db_info->{host}, $db_info->{port});
	my $dbh;
	eval {
	    $dbh =
	      DBI->connect($dsn, $db_info->{user}, $db_info->{password},
	        { RaiseError => 1, AutoCommit => 1, PrintError => 0 });
		$dbh->{pg_enable_utf8} = 1;
	};
	if ($@) {
		carp "Failed to connect to database: $@";
	}

	if(defined($dbh)) {
		$self->{dbh} = $dbh;
	} else {
		croak "Cannot connect to database";
	}

	bless $self, $class;
	return $self;
}

# Fires of a new check
sub start_check {
	my ($self, $domain, $source, $source_data) = @_;

	# Lets see if we have source id
	my $source_id = $self->get_source_id($source);

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		INSERT INTO
		queue (domain, priority, source_id, source_data, fake_parent_glue)
		VALUES (?, 10, ?, ?, ?)})
		or die "Could not prepare statement";
	$query->execute($domain, $source_id, $source_data, $source_data);
}

# Returns id for the given source, or creates a new one.
sub get_source_id {
	my($self, $source) = @_;

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		SELECT id FROM source WHERE name = ?})
		or die "Could not prepare statement";
	$query->execute($source);

	my $result = $query->fetchrow_arrayref;
	# Insert new source
	if(!defined($result)) {
		$query = $dbh->prepare(q{ INSERT INTO source (name) VALUES (?) });
		$query->execute($source) or die "Database query failed";

		return $dbh->last_insert_id(undef, undef, qw(source id));
	} else {
		# Dereference and return result
		return @$result[0];
	}
}

# Checks the queue for a running result
sub get_running_result {
	my ($self, $domain, $source, $source_data) = @_;

	my $query = $self->{dbh}->prepare(q{
		(SELECT
			NULL AS id, NULL AS time, 'NO' AS finished,
			source_data AS source_data
		FROM queue
			INNER JOIN
				source ON source.id = queue.source_id
				AND source.name = ?
		WHERE
			queue.domain = ? AND queue.source_data = ?)
		UNION
		(SELECT
			tests.id AS id, date_part('epoch', tests.started) AS TIME,
			CASE tests.finished WHEN NULL THEN 'NO' ELSE 'YES' END AS finished,
			source_data AS source_data
		FROM tests
			INNER JOIN
				source ON source.id = tests.source_id AND source.name = ?
		WHERE
			tests.domain = ? and tests.source_data = ?
			AND (tests.finished = null
			OR (date_part('epoch', now()) - date_part('epoch',
			tests.finished)) < 300))
	}) or die "Prepare statement failed";

	$query->execute($source, $domain, $source_data, $source, $domain,
	$source_data) or die "Could not execute query";

	return $query->fetchall_arrayref;
}
# Fetch the test_id for a running case
sub get_running_test_id {
	my ($self, $domain, $source, $source_data) = @_;
	my $query = $self->{dbh}->prepare(q{
		SELECT test.id AS id
		FROM tests AS test
			INNER JOIN queue ON
			queue.domain = test.domain
			AND queue.source_id = test.source_id
			AND queue.source_data = test.source_data
		WHERE
			test.domain = ?
			AND test.source_data = ?
			AND test.finished IS NULL
		LIMIT 1;
	}) or die "Prepare statement failed";
	$query->execute($domain, $source_data) or die "Execute failed";
	return $query->fetchrow_hashref;
}

sub get_last_test_id {
	my ($self, $domain, $source, $source_data) = @_;
	my $query = $self->{dbh}->prepare(q{
		SELECT test.id AS id
		FROM tests AS test
		WHERE
			test.domain = ?
			AND test.source_data = ?
		ORDER BY id DESC
		LIMIT 1;
	}) or die "Prepare statement failed";
	$query->execute($domain, $source_data) or die "Execute failed";
	return $query->fetchrow_hashref;
}

# Call to check whether the results are ready, or still being processed
sub get_running_result_on_id {
	my ($self, $test_id) = @_;
	
	my $query = $self->{dbh}->prepare(q{
		SELECT 
			CASE
				WHEN finished IS NULL THEN 'NO' 
				ELSE 'YES' 
			END AS finished
		FROM tests
		WHERE id = ?;
	});
	$query->execute($test_id);
	return $query->fetchrow_hashref;
}

# Returns all test results for a given test id. Joins on messages for those
# results (using the locale).
sub get_test_results {
	my ($self, $test_id, $locale) = @_;

	my $query = $self->{dbh}->prepare(q{
		SELECT *
		FROM (
			SELECT *
			FROM results
			WHERE results.test_id = ? AND results.degree != 'DEBUG'
		) AS tmp
		LEFT JOIN messages ON
		tmp.message = messages.tag
		AND messages.language = ?
		ORDER BY tmp.id ASC}) or die "Prepare statement failed";
	$query->execute($test_id, $locale) or die "Execute failed";

	return $query->fetchall_arrayref;
}

# Returns the latest test history for the given test id
sub get_history {
	my ($self, $test_id) = @_;
	# Could constraint join on source_data also.
	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		SELECT 
			test2.id, 
			to_char(test2.started, 'YYYY-MM-DD  HH24:MI:SS') AS time,
			CASE
				WHEN test2.count_error > 0 THEN 'error' 
				WHEN test2.count_warning > 0 THEN 'warning' 
				ELSE 'ok' 
			END AS status
		FROM tests AS test1 
			INNER JOIN tests AS test2 ON test1.domain = test2.domain
			AND test1.source_id = test2.source_id 
			AND test1.source_data = test2.source_data
		WHERE test1.id = ?
		ORDER BY test2.id DESC
		LIMIT 5;
	}) or die "Prepare statement failed";
	$query->execute($test_id);

	return $query->fetchall_arrayref;
}

# Returns the version of DNSChecker that we are running.
sub get_version {
	my $self = shift;

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		SELECT arg1
		FROM results
		WHERE message = 'ZONE:BEGIN' and test_id = (select max(test_id) from results)
		ORDER BY test_id DESC LIMIT 1;});
	$query->execute();

	return $query->fetchrow_arrayref->[0];
}

1;
