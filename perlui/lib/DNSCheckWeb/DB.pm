#!/usr/bin/perl
#
# Module for all database interaction.
#
use warnings;
use strict;

package DNSCheckWeb::DB;

use Carp;
use Data::Dumper;

my $dbo;

sub new {
	my ($class, $config) = @_;

	# Check that we have database information
	unless(defined($config) || defined($config->{dbi})) {
		die DBException->throw( error => "No database information provided.");
	}

	# Assign database meta information on the specified type
	my $dbi = $config->{dbi};
	my $db_meta = $config->{$dbi->{type}};

	# Check that given database type matches one in config
	unless(defined($db_meta)) {
		die DBException->throw( error => "Could not load db information for the type: $dbi->{type}");
	}

	# Construct connect statement
	my $dsn  = sprintf($db_meta->{driver}, $dbi->{database}, $dbi->{host}, $dbi->{port});
	# Do connection
	my $dbh = DBI->connect($dsn, $dbi->{user}, $dbi->{password}, {
		RaiseError => 0, AutoCommit => 1, PrintError => 0, pg_enable_utf8 => 1
	})
	or die DBException->throw( error=> $DBI::errstr);

	# Assign reference if everything worked out
	my $self = { };
	if(defined($dbh)) {
		$self->{dbh} = $dbh;
	} else {
		DBException->throw( error => "Could not connect to database");
	}

	bless $self, $class;
	return $self;
}

# Fires of a new check
sub start_check {
	my ($self, $domain, $source, $source_data) = @_;

	# Check that source already exist
	my $source_id = $self->get_source_id($source);

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		INSERT INTO
		queue (domain, priority, source_id, source_data, fake_parent_glue)
		VALUES (?, 10, ?, ?, ?)})
		or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($domain, $source_id, $source_data, $source_data)
	or die DBException->throw( error => $self->{dbh}->errstr);
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
		$query = $dbh->prepare(q{ INSERT INTO source (name) VALUES (?) })
		or die DBException->throw( error => $self->{dbh}->errstr);
		$query->execute($source)
		or die DBException->throw( error => $self->{dbh}->errstr);

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
			source_data AS source_data,
			inprogress AS started
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
			source_data AS source_data,
			NULL AS started
		FROM tests
			INNER JOIN
				source ON source.id = tests.source_id AND source.name = ?
		WHERE
			tests.domain = ? and tests.source_data = ?
			AND (tests.finished = NULL
			OR (date_part('epoch', now()) - date_part('epoch',
			tests.finished)) < 300)
		LIMIT 1)
	})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($source, $domain, $source_data, $source, $domain, $source_data)
	or die DBException->throw( error => $self->{dbh}->errstr);

	return $query->fetchrow_hashref;
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
	})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($domain, $source_data)
	or die DBException->throw( error => $self->{dbh}->errstr);

	return $query->fetchrow_hashref;
}

# Get last inserted test_id
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
	})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($domain, $source_data)
	or die DBException->throw( error => $self->{dbh}->errstr);

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
	})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($test_id)
	or die DBException->throw( error => $self->{dbh}->errstr);

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
			WHERE results.test_id = ? AND results.class != 'DEBUG'
		) AS tmp
		LEFT JOIN messages ON
		tmp.message = messages.tag
		AND messages.language = ?
		ORDER BY tmp.id ASC})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($test_id, $locale)
	or die DBException->throw( error => $self->{dbh}->errstr);

	return $query->fetchall_arrayref;
}

# Returns the latest test history for the given test id
sub get_history {
	my ($self, $test_id) = @_;

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		SELECT
			test2.id AS id,
			to_char(test2.started, 'YYYY-MM-DD  HH24:MI:SS') AS time,
			CASE
				WHEN test2.count_error > 0 THEN 'error'
				WHEN test2.count_warning > 0 THEN 'warning'
				ELSE 'ok'
			END AS class
		FROM tests AS test1
			INNER JOIN tests AS test2 ON test1.domain = test2.domain
			AND test1.source_id = test2.source_id
			AND test1.source_data = test2.source_data
			AND test1.id != test2.id
		WHERE test1.id = ?
		ORDER BY id DESC
		LIMIT 5;
	})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($test_id)
	or die DBException->throw( error => $self->{dbh}->errstr);

	return $query->fetchall_arrayref;
}

sub get_test_data {
	my ($self, $test_id) = @_;

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		SELECT
			to_char(started, 'YYYY-MM-DD  HH24:MI:SS') AS started,
			to_char(finished, 'YYYY-MM-DD  HH24:MI:SS') AS finished,
			count_critical AS critical,
			count_error AS error,
			count_warning AS warning,
			count_notice AS notice,
			count_info AS info
		FROM tests
		WHERE id = ?
	})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute($test_id)
	or die DBException->throw( error => $self->{dbh}->errstr);

	return $query->fetchrow_hashref;
}

# Returns the version of DNSChecker that we are running.
sub get_version {
	my $self = shift;

	my $dbh = $self->{dbh};
	my $query = $dbh->prepare(q{
		SELECT arg1 AS version
		FROM results
		WHERE message = 'ZONE:BEGIN' and test_id = (select max(test_id) from results)
		ORDER BY test_id DESC LIMIT 1;})
	or die DBException->throw( error => $self->{dbh}->errstr);
	$query->execute()
	or die DBException->throw( error => $self->{dbh}->errstr);

	return $query->fetchrow_hashref;
}

1;
