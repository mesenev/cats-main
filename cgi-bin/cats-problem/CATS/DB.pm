use strict;
use warnings;

package CATS::DB::Firebird;

sub new {
    my $class = shift;
    my $self = {
        BLOB_TYPE => 'BLOB',
        TEXT_TYPE => 'BLOB SUB_TYPE TEXT',
        LIMIT => 'ROWS',
        FROM_DUMMY => 'FROM RDB$DATABASE',
        LAST_IP_QUERY => q~
            SELECT mon$remote_address FROM mon$attachments M
            WHERE M.mon$attachment_id = CURRENT_CONNECTION~,
    };
    bless $self, $class;
}

sub next_sequence_value {
    $CATS::DB::dbh->selectrow_array(qq~SELECT GEN_ID($_[1], 1) FROM RDB\$DATABASE~);
}

sub current_sequence_value {
    $CATS::DB::dbh->selectrow_array(qq~SELECT GEN_ID($_[1], 0) FROM RDB\$DATABASE~);
}

sub bind_blob {
    my ($self, $sth, $p_num, $blob) = @_;
    $sth->bind_param($p_num, $blob);
}

sub enable_utf8 {
    $CATS::DB::dbh->{ib_enable_utf8} = 1;
}

sub disable_utf8 {
    $CATS::DB::dbh->{ib_enable_utf8} = 0;  
}

sub catch_deadlock_error {
    my ($self, $warn_prefix) = @_;
    my $err = $@ // '';
    $err =~ /concurrent transaction number is (\d+)/m or die $err;
    warn "$warn_prefix: deadlock with transaction: $1" if $warn_prefix;
    undef;
}

sub foreign_key_violation {
    $_[0] =~ /violation of FOREIGN KEY constraint "\w+" on table "(\w+)"/ && $1;
}

sub format_date { 
    $_[1] or return;
    $_[1] =~ s/\s*$//;
    $_[1];
}

sub parse_date {
    $_[1] || undef;
}

sub make_dsn {
    sprintf 'dbi:Firebird:dbname=%s;host=%s;ib_charset=UTF8;ib_role=%s',
        $CATS::Config::db->{name}, $CATS::Config::db->{host}, $CATS::Config::db->{role} // '';
}

package CATS::DB::Postgres;

use Encode;

sub new {
    my $class = shift;
    my $self = {
        BLOB_TYPE => 'BYTEA',
        TEXT_TYPE => 'TEXT',
        LIMIT => 'LIMIT',
        FROM_DUMMY => '',
        LAST_IP_QUERY => 'SELECT CAST(INET_CLIENT_ADDR() AS TEXT)',
    };
    bless $self, $class;
}

sub next_sequence_value {
    $CATS::DB::dbh->selectrow_array(qq~SELECT NEXTVAL('$_[1]')~);
}

sub current_sequence_value {
    $CATS::DB::dbh->selectrow_array(qq~SELECT LAST_VALUE FROM $_[1]~);
}

sub bind_blob {
    my ($self, $sth, $p_num, $blob) = @_;
    Encode::_utf8_off($blob);
    $sth->bind_param($p_num, $blob, { pg_type => 17 });
}

sub enable_utf8 {
    $CATS::DB::dbh->{pg_enable_utf8} = -1; # Default value.
}

sub disable_utf8 {
    $CATS::DB::dbh->{pg_enable_utf8} = 0;
}

sub catch_deadlock_error {
    my ($self, $warn_prefix) = @_;
    my $err = $@ // '';
    $err =~ /Process \d+ waits for ShareLock on transaction (\d+)/ or die $err;
    warn "$warn_prefix: deadlock with transaction: $1" if $warn_prefix;
    undef;
}

sub foreign_key_violation {
    $_[0] =~ /insert or update on table "(\w+)" violates foreign key constraint "\w+"/ && $1;
}

sub format_date {
    $_[1] or return;
    $_[1] =~ /^\s*(\d+)-(\d+)-(\d+)\s*(\d+:\d+)?/; # Ignore milliseconds and time zone at the end.
    $4 ? "$3.$2.$1 $4" : "$3.$2.$1";
}

sub parse_date {
    $_[1] or return;
    $_[1] =~ /^\s*(\d+)\.(\d+)\.(\d+)\s*(\d+:\d+)$/;
    "$3-$2-$1 $4";
}

sub make_dsn {
    "dbi:Pg:dbname=$CATS::Config::db->{name};host=$CATS::Config::db->{host};";
}

package CATS::DB;

use Encode;

use Exporter qw(import);
our @EXPORT = qw($dbh $sql new_id _u);
our @EXPORT_OK = qw($db);

use Carp;
use DBI;

use CATS::Config;

our ($dbh, $sql, $db);

sub _u { splice(@_, 1, 0, { Slice => {} }); @_; }

sub select_row {
    $dbh->selectrow_hashref(_u $sql->select(@_));
}

sub new_id {
    return Digest::MD5::md5_hex(Encode::encode_utf8($_[1] // die))
        unless $CATS::DB::dbh;
    $db->next_sequence_value('key_seq');
}

sub sql_connect {
    my ($db_options) = @_;

    if ($CATS::Config::db->{driver} =~ /Firebird/) {
        $db = CATS::DB::Firebird->new;
    } elsif ($CATS::Config::db->{driver} =~ /Pg/) {
        $db = CATS::DB::Postgres->new;
    } else {
        die 'Error in sql_connect';
    }

    if ($dbh && !$dbh->ping) {
        eval { $dbh->disconnect };
        undef $dbh;
    }
    $dbh ||= DBI->connect(
        $db->make_dsn, $CATS::Config::db->{user}, $CATS::Config::db->{password},
        {
            AutoCommit => 0,
            LongReadLen => 1024*1024*20,
            FetchHashKeyName => 'NAME_lc',
            RaiseError => 1,
            %$db_options,
        }
    ) or die "Failed connection to SQL-server $DBI::errstr";

    $db->enable_utf8;
    $dbh->{HandleError} = sub {
        my $m = "DBI error: $_[0]\n";
        croak $m;
        0;
    };

    $sql ||= SQL::Abstract->new if $SQL::Abstract::VERSION;
}

sub sql_disconnect {
    $dbh or return;
    $dbh->disconnect;
    undef $dbh;
}

1;
