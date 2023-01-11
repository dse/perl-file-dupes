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
our $PROGRESS_EVERY = 233;

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
    my $dry_run  = $options{dry_run};
    my $verify   = $options{verify};
    my $progress = $options{progress};

    my %is_a_first_filename;
    my %by_basename;
    my %index;
    my $index = 0;
    foreach my $dir (@dirs) {
        if ($verbose) {
            warn("Finding files in ${dir} ...\n");
        }
        my $count = 0;
        my $wanted = sub {
            if ($progress) {
                $count += 1;
                progress("%d files found", $count) if $count % $PROGRESS_EVERY == 0;
            }
            my $basename = $_;
            my $filename = $File::Find::name;

            my @lstat = lstat($_);
            return if (!scalar @lstat);
            return if (-d _) || (!-f _) || (-s _ < $min_size);

            my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = @lstat;
            $is_a_first_filename{$filename} = 1;
            push(@{$by_basename{$basename}}, { filename => $filename, dev => $dev, ino => $ino, size => $size });
            $index{$filename} = ++$index; # in order in which directories are specified
        };
        progress() if $progress;
        File::Find::find({ wanted => $wanted }, $dir);
        progress() if $progress;
        if ($verbose) {
            printf STDERR ("%d files found\n", $count);
        }
    }
    my @results;
    my $total = scalar keys %by_basename;
    if ($verbose) {
        progress();
        printf STDERR ("%d basenames found; removing non-duplicates\n", $total);
    }
    foreach my $basename (keys %by_basename) {
        if (scalar @{$by_basename{$basename}} < 2) {
            delete $by_basename{$basename};
            $total -= 1;
            if ($progress) {
                progress("%d basenames found", $total) if $total % $PROGRESS_EVERY == 0;
            }
        }
    }
    if ($verbose) {
        progress();
        printf STDERR ("%d basenames total after removing non-duplicates\n", $total);
    }
    my $count = 0;
    foreach my $basename (keys %by_basename) {
        if ($progress) {
            $count += 1;
            progress("%d/%d", $count, $total) if $count % $PROGRESS_EVERY == 0;
        }
        my @by_basename = @{$by_basename{$basename}};
        next if scalar @by_basename < 2;
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
                my @group_filenames = @$file_group;
                push(@results, [@group_filenames]) if defined wantarray;
                if ($callback && ref $callback eq 'CODE') {
                    my %args = (
                        filenames => \@group_filenames,
                        hard_link_groups => \%hard_link_groups,
                        verbose => $verbose,
                        dry_run => $dry_run,
                        verify => $verify,
                        progress => $progress,
                    );
                    {
                        my ($junk, @filenames) = @group_filenames;
                        if (grep { $is_a_first_filename{$_} } @filenames) {
                            warn("failed not-the-first-filename check:\n");
                            foreach my $filename (@group_filenames) {
                                if ($is_a_first_filename{$filename}) {
                                    warn("*   $filename\n");
                                } else {
                                    warn("    $filename\n");
                                }
                            }
                            die();
                        }
                    }
                    &$callback(%args);
                }
            }
        }
    }
    progress();
    return @results if wantarray;
    return [@results] if defined wantarray;
}

sub progress {
    state $ready = 1;
    return unless -t 2;
    my ($format, @args) = @_;
    if (!defined $format) {
        return if $ready;
        print STDERR "\r\e[K";
        $ready = 1;
        return;
    }
    $ready = 0;
    my $string = sprintf($format, @args);
    print STDERR "\r" . $string . "\e[K";
}

1;
