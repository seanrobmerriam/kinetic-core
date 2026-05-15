#!/usr/bin/env perl
use strict;
use warnings;
use File::Slurp;

my @files = (
    "apps/cb_contracts/test/cb_contracts_execute_SUITE.erl",
    "apps/cb_contracts/test/cb_contract_registry_SUITE.erl",
    "apps/cb_contracts/test/cb_contract_experiments_SUITE.erl",
);

for my $f (@files) {
    my $content = read_file($f);
    # Quote bare reserved-word map keys that are not already quoted
    $content =~ s/(?<!')when(?!') =>/'when' =>/g;
    $content =~ s/(?<!')then(?!') =>/'then' =>/g;
    $content =~ s/(?<!')else(?!') =>/'else' =>/g;
    write_file($f, $content);
    print "Fixed $f\n";
}
