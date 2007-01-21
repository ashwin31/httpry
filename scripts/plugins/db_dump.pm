#!/usr/bin/perl -w

#
# Copyright (c) 2005-2007, Jason Bittel <jason.bittel@gmail.com>. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the author nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

package db_dump;

use DBI;

# -----------------------------------------------------------------------------
# GLOBAL VARIABLES
# -----------------------------------------------------------------------------
my $dbh;

# -----------------------------------------------------------------------------
# Plugin core
# -----------------------------------------------------------------------------

&main::register_plugin(__PACKAGE__);

sub new {
        return bless {};
}

sub init {
        my $self = shift;
        my $plugin_dir = shift;
        my $sql;
        my $limit;

        if (&load_config($plugin_dir) == 0) {
                return 0;
        }

        $dbh = &connect_db($type, $db, $host, $port, $user, $pass);

        # Delete data inserted $rmbefore days prior
        if ($rmbefore > 0) {
                my ($year, $mon, $day, $hour, $min, $sec) = (localtime(time-(86400*$rmbefore)))[5,4,3,2,1,0];
                $limit = ($year+1900) . "-" . ($mon+1) . "-$day $hour:$min:$sec";

                $sql = qq{ DELETE FROM client_data WHERE timestamp < '$limit' };
                &execute_query($dbh, $sql);
                
                $sql = qq{ DELETE FROM server_data WHERE timestamp < '$limit' };
                &execute_query($dbh, $sql);
        }

        return 1;
}

sub main {
        my $self   = shift;
        my $record = shift;
        my $sql    = "";
        my ($year, $mon, $day, $hour, $min, $sec) = (localtime)[5,4,3,2,1,0];
        my $now = ($year+1900) . "-" . ($mon+1) . "-$day $hour:$min:$sec";
        my $timestamp;
        my $request_uri;

        # Make sure we really want to be here
        return unless exists $record->{"direction"};
        return unless exists $record->{"timestamp"};
        return unless exists $record->{"source-ip"};
        return unless exists $record->{"dest-ip"};
        
        # Reformat packet date/time string
        $record->{"timestamp"} =~ /(\d\d)\/(\d\d)\/(\d\d\d\d) (\d\d):(\d\d):(\d\d)/;
        $timestamp = "$3-$1-$2 $4:$5:$6";

        if ($record->{"direction"} eq '>') {
                return unless exists $record->{"host"};
                return unless exists $record->{"request-uri"};

                $request_uri = quotemeta($record->{"request-uri"});

                $sql = qq{ INSERT INTO client_data (timestamp, pktstamp, src_ip, dst_ip, hostname, uri)
                           VALUES ('$now', '$timestamp', '$record->{"source-ip"}', '$record->{"dest-ip"}',
                           '$record->{"host"}', '$request_uri') };
        } elsif ($record->{"direction"} eq '<') {
                return unless exists $record->{"status-code"};
                return unless exists $record->{"reason-phrase"};

                $sql = qq{ INSERT INTO server_data (timestamp, pktstamp, src_ip, dst_ip, status_code, reason_phrase)
                           VALUES ('$now', '$timestamp', '$record->{"source-ip"}', '$record->{"dest-ip"}',
                           '$record->{"status-code"}', '$record->{"reason-phrase"}') };
        }

        &execute_query($dbh, $sql) if $sql;
        
        return;
}

sub end {
        &disconnect_db();

        return;
}

# -----------------------------------------------------------------------------
# Load config file and check for required options
# -----------------------------------------------------------------------------
sub load_config {
        my $plugin_dir = shift;

        # Load config file; by default in same directory as plugin
        if (-e "$plugin_dir/" . __PACKAGE__ . ".cfg") {
                require "$plugin_dir/" . __PACKAGE__ . ".cfg";
        }

        # Check for required options and combinations
        if (!$type) {
                print "Error: No database type provided\n";
                return 0;
        }
        if (!$db) {
                print "Error: No database name provided\n";
                return 0;
        }
        if (!$host) {
                print "Error: No database hostname provided\n";
                return 0;
        }
        $port = '3306' unless ($port);

        return 1;
}

# -----------------------------------------------------------------------------
# Build connection to specified database
# -----------------------------------------------------------------------------
sub connect_db {
        my $type = shift;
        my $db   = shift;
        my $host = shift;
        my $port = shift;
        my $user = shift;
        my $pass = shift;
        my $dbh;
        my $dsn;

        $dsn = "DBI:$type:$db";
        $dsn .= ":$host" if $host;
        $dsn .= ":$port" if $port;

        $dbh = DBI->connect($dsn, $user, $pass, { RaiseError => 1, AutoCommit => 1 })
                or die "Error: Cannot connect to database: " . DBI->errstr . "\n";

        &execute_query($dbh, qq{ USE $db });

        return $dbh;
}

# -----------------------------------------------------------------------------
# Generalized SQL query execution sub
# -----------------------------------------------------------------------------
sub execute_query {
        my $dbh = shift;
        my $sql = shift;
        my $sth;

        $sth = $dbh->prepare($sql) or die "Error: Cannot prepare query: " . DBI->errstr . "\n";
        $sth->execute() or die "Error: Cannot execute query: " . DBI->errstr . "\n";

        return $sth;
}

# -----------------------------------------------------------------------------
# Terminate active database connection
# -----------------------------------------------------------------------------
sub disconnect_db {
        $dbh->disconnect;
}

1;
