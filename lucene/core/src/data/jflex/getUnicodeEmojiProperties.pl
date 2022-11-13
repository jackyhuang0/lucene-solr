#!/usr/bin/perl

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use warnings;
use strict;
use File::Spec;
use Getopt::Long;
use LWP::UserAgent;

my ($volume, $directory, $script_name) = File::Spec->splitpath($0);

my $version = '';
unless (GetOptions("version=s" => \$version) && $version =~ /\d+\.\d+/) {
    print STDERR "Usage: $script_name -v <version>\n";
    print STDERR "\tversion must be of the form X.Y, e.g. 9.0\n"
        if ($version);
    exit 1;
}
my $emoji_data_url = "http://unicode.org/Public/emoji/$version/emoji-data.txt";
my $output_filename = "UnicodeEmojiProperties.jflex";
my $header =<<"__HEADER__";
/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// This file was automatically generated by ${script_name}
// from: ${emoji_data_url} 

__HEADER__

my $property_ranges = {};
my $wanted_properties = { 'Emoji' => 1, 'Emoji_Modifier' => 1, 'Emoji_Modifier_Base' => 1, 'Extended_Pictographic' => 1 };

parse_emoji_data_file($emoji_data_url, $property_ranges, $wanted_properties);

my $output_path = File::Spec->catpath($volume, $directory, $output_filename);
output_jflex_include_file($output_path, $property_ranges);


# sub parse_emoji_data_file
#
# Downloads and parses the emoji_data.txt file, extracting code point ranges
# assigned to property values with age not younger than the passed-in version,
# except for the Extended_Pictographic property, for which all code point ranges
# are extracted, regardless of age.
#
# Parameters:
#
#  - Emoji data file URL
#  - Reference to hash of properties mapped to an array of alternating (start,end) code point ranges
#  - Reference to hash of wanted property names
#
sub parse_emoji_data_file {
    my $url = shift;
    my $prop_ranges = shift;
    my $wanted_props = shift;
    my $content = get_URL_content($url);
    print STDERR "Parsing '$url'...";
    my @lines = split /\r?\n/, $content;
    for (@lines) {
        ## 231A..231B    ; Emoji_Presentation   #  1.1  [2] (⌚..⌛)    watch..hourglass done
        ## 1F9C0         ; Emoji_Presentation   #  8.0  [1] (🧀)       cheese wedge
        ## 1FA00..1FA5F  ; Extended_Pictographic#   NA [96] (🨀️..🩟️)    <reserved-1FA00>..<reserved-1FA5F>
        if (my ($start,$end,$prop) = /^([0-9A-F]{4,5})(?:\.\.([0-9A-F]{4,5}))?\s*;\s*([^\s#]+)/) {
            next unless defined($wanted_props->{$prop});  # Skip unless we want ranges for this property
            
            if (not defined($prop_ranges->{$prop})) {
                $prop_ranges->{$prop} = [];
            }
            $end = $start unless defined($end);
            my $start_dec = hex $start;
            my $end_dec = hex $end;
            my $ranges = $prop_ranges->{$prop};
            if (scalar(@$ranges) == 0 || $start_dec > $ranges->[-1] + 1) { # Can't merge range with previous range
                # print STDERR "Adding new range ($start, $end)\n";
                push @$ranges, $start_dec, $end_dec;
            } else {
                # printf STDERR "Merging range (%s, %s) with previous range (%X, %X)\n", $start, $end, $ranges->[-2], $ranges->[-1];
                $ranges->[-1] = $end_dec;
            }
        } else {
            # print STDERR "Skipping line (no data): $_\n";
        }
    }
    print STDERR "done.\n";
}

# sub get_URL_content
#
# Retrieves and returns the content of the given URL.
#
# Parameter:
#
#  - URL to get content for
#
sub get_URL_content {
    my $url = shift;
    print STDERR "Retrieving '$url'...";
    my $user_agent = LWP::UserAgent->new;
    my $request = HTTP::Request->new(GET => $url);
    my $response = $user_agent->request($request);
    unless ($response->is_success) {
        print STDERR "Failed to download '$url':\n\t",$response->status_line,"\n";
        exit 1;
    }
    print STDERR "done.\n";
    return $response->content;
}


# sub output_jflex_include_file
#
# Parameters:
#
#  - Output path
#  - Reference to hash mapping properties to an array of alternating (start,end) codepoint ranges
#     
sub output_jflex_include_file {
    my $path = shift;
    my $prop_ranges = shift;
    open OUT, ">$path"
        || die "Error opening '$path' for writing: $!";

    print STDERR "Writing '$path'...";

    print OUT $header;

    for my $prop (sort keys %$prop_ranges) {
        my $ranges = $prop_ranges->{$prop};
        print OUT "$prop = [";
        for (my $index = 0 ; $index < scalar(@$ranges) ; $index += 2) {
            printf OUT "\\u{%X}", $ranges->[$index];
            printf OUT "-\\u{%X}", $ranges->[$index + 1] if ($ranges->[$index + 1] > $ranges->[$index]);
        }
        print OUT "]\n";
    }

    print OUT "\n";
    close OUT;
    print STDERR "done.\n";
}