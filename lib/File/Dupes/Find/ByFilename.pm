package File::Dupes::Find::ByFilename;
use warnings;
use strict;
use feature qw(state);

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(find_by_filename);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

our $DEFAULT_MIN_SIZE = 1048576;

use File::Find;

use lib "../../..";
use File::Dupes qw(check_for_dupes
                   group_hard_links);

sub find_by_filename {
    my @dirs;
    my %options;
    foreach my $arg (@_) {
        next if !defined $arg;
        if (ref $arg eq 'ARRAY') {
            push(@dirs, @$arg);
        } elsif (ref $arg eq 'HASH') {
            %options = (%options, %$arg);
        } elsif (ref $arg eq '') {
            push(@dirs, $arg);
        }
    }
    my $min_size = $options{min_size} // $DEFAULT_MIN_SIZE;
    my $callback = $options{callback};
    my $verbose  = $options{verbose};
    my %by_basename;
    my %index;
    my $index = 0;
    foreach my $dir (@dirs) {
        if ($verbose) {
            warn("Finding files in ${dir} ...\n");
        }
        my $wanted = sub {
            my $basename = $_;
            my $filename = $File::Find::name;
            my @lstat = lstat($_);
            return if (!scalar @lstat);
            return if (-d _) || (!-f _) || (-s _ < $min_size);
            my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = @lstat;
            push(@{$by_basename{$basename}}, { filename => $filename, dev => $dev, ino => $ino, size => $size });
            $index{$filename} = ++$index; # in order in which directories are specified
        };
        File::Find::find({ wanted => $wanted }, $dir);
    }
    my @results;
    foreach my $basename (keys %by_basename) {
        my @by_basename = @{$by_basename{$basename}};
        my %filenames_by_dev_ino;
        foreach my $record (@by_basename) {
            my $dev = $record->{dev};
            my $ino = $record->{ino};
            push(@{$filenames_by_dev_ino{$dev,$ino}}, $record->{filename});
        }
        my %size_by_filename;
        foreach my $record (@by_basename) {
            my $filename = $record->{filename};
            my $size = $record->{size};
            $size_by_filename{$filename} = $size;
        }
        my %hardlinks_by_main_filename;
        foreach my $key (keys %filenames_by_dev_ino) {
            my @filenames = @{$filenames_by_dev_ino{$key}};
            my $main_filename = $filenames[0];
            $hardlinks_by_main_filename{$main_filename} = $filenames_by_dev_ino{$key};
        }
        my @main_filenames = sort keys %hardlinks_by_main_filename;
        my %main_filenames_by_size;
        foreach my $main_filename (@main_filenames) {
            my $size = $size_by_filename{$main_filename};
            push(@{$main_filenames_by_size{$size}}, $main_filename);
        }
        foreach my $size (keys %main_filenames_by_size) {
            my @main_filenames = @{$main_filenames_by_size{$size}};
            next if scalar @main_filenames < 2;
            @main_filenames = sort { ($index{$a} <=> $index{$b}) || ($a cmp $b) } @main_filenames;
            my %hard_link_groups;
            foreach my $main_filename (@main_filenames) {
                $hard_link_groups{$main_filename} = $hardlinks_by_main_filename{$main_filename};
            }
            my @file_groups = check_for_dupes(@main_filenames);
            foreach my $file_group (@file_groups) {
                my @group_filenames = map { $_->{filename} } @$file_group;
                push(@results, [@group_filenames]) if defined wantarray;
                if ($callback && ref $callback eq 'CODE') {
                    &$callback(filenames => \@group_filenames,
                               hard_link_groups => \%hard_link_groups);
                }
            }
        }
    }
    return @results if wantarray;
    return [@results] if defined wantarray;
}

1;
