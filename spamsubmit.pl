#!/usr/bin/perl -w

# Parses emails from the batch files of spamdata (reads a directory) available off 
# of mailsvcs
# robarn@corp.earthlink.net

use strict;

my $uuencode = '/usr/bin/uuencode';
my $mail = '/usr/bin/mailx';
my $gzip = '/usr/local/bin/gzip';
my $outfile = $ENV{'HOME'} . '/out.txt';
my $uuout = $outfile . '.gz';

####################################


sub open_fail { die "$0: cannot open $_[0]: $!\n" }

my ($dir,$subdir) = &prevhour;
my $batchdir = "/mail/spam2/spamsubmit/$dir/$subdir/false_negative";

opendir(D, $batchdir) or die open_fail ($batchdir);
my @files = map { "$batchdir/" . $_ } grep { ! /^\./ } readdir D;

my $rfc1918 = '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)';

open OUT, ">$outfile"
    or die "can't open $outfile for writing: $!\n";
print "parsing $batchdir...\n";
foreach my $batch (@files) {
    my $arrayref = getmail ($batch);
    foreach my $array (@$arrayref) { # iterate thru the array of headers
        my $href = headers ($array); # parse each header array into a hash that has isolated each attribute we want
        # Now insert the isolated header attributes into the database.

        my $newip = $href->{'ip'};
        my $subject = $href->{'subject'};
        my $date = $href->{'date'};
        my $from = $href->{'from'};	

        if ($newip eq 'NULL') {
            print STDERR "DEBUG: no IP found for $batch\n";
            #$errbase = basename ($msg);
            #copy($msg,"$debugdir/$errbase");
            next;
            # we don't want to match IP space reserved for private use as provisioned  RFC1918
        } elsif ($newip =~ /$rfc1918/o) {
            print STDERR "DEBUG: rfc1918 space for $batch\n";
            #$errbase = basename ($msg);
            #copy($msg,"$debugdir/$errbase");
            next;
        }


        (/$0:NULL/) and  $_ = 'N/A' for ($newip,$date,$from,$subject);

        my $text= "\n<Message>\nIP: $newip\nDate: $date\nFrom: $from\nSubject: $subject\n</Message>\n";
        print OUT $text;

    } # end foreach my $array
} # end foreach my $batch

close OUT;
print "gzipping...\n";

system("$gzip $outfile > /dev/null 2>&1");

print "encoding, mailing....\n";
system("$uuencode < $outfile $uuout|$mail -s \"testing sending mail from mailsvcs\" fbl\@antiphon.abuse.earthlink.net");

#unlink $outfile;

print "...done.\n";






# extracts each header part of the batch email
# returns it as a reference to an array of array references
sub getmail {
    my $batch = $_[0];
    # some regex we'll use
    my $text = '(\d+) message\(s\) reported as spam';
    my $date = '\w{3}\,\s\d+\s\w{3}\s\d{4}\s\d{2}:\d{2}:\d{2}\s-\d{4}\s\([A-Z]{3}\)';

    # initialize  loop variables

    my $num = 0; # number of mime attachments
    my $boundary = 0;
    my $blank = 0;
    my $msg = 0;
    my $hdr = 0;
    my @email = ();
    my @messages = ();
    #my $count = 0;

    open BATCH, $batch
        or die "can't open $batch: $!\n";

    # Main Loop.
    # Isolate ***just the headers** of each attached message. Cue off the initial MIME boundary
    # to find each group of headers. The bodies of each message are skipped.
    while (<BATCH>) {
        unless ($num) {
            /boundary=\"?(.+)\"/ and $boundary = '--' . $1;
        } # end unless

        /$text/o and $num = $1; # the number of attached messages

        if (($num) && (!$boundary)) {
            #open_fail (*STDERR, "Message not in expected MIME format");
            print STDERR "Message not in expected MIME format\n";
            exit 0; 
        }

        if (($num) && ($boundary)) { # if here, we are in the body proper
            # The next boundary set hdr var so we know we are "in the headers"
            # Set var $blank to zero, to find the next blank line....
            if (/^$boundary/) {
                #print "debug: found boundary, looking for next blank line...\n";
                $hdr = 1;
                $blank = 0;
                next;
            }	


            unless ($blank) {
                /^$/ and $blank = 1, next; # we've entered an attached message, next line will start the headers
                # that we're looking for!
            }

            if ($blank) {
                if ((/^$/) && ($hdr)) {
                    $hdr = 0;
                    #print "debug:", @email;
                    push(@messages,[ @email ]);
                    @email = ();
                    next;
                }else{
                    if ($hdr) {
                        #print "debug: pushing $_";
                        push(@email,$_);
                    } else {
                        #print "debug: next-ing, looking for $boundary\n";
                        next;
                    }	
                }	
            } # end if $blank
        } # end if num and boundary
    } # end main loop


    return \@messages;


} # end sub get mail

# takes array reference to raw header info
# returns a hash reference with keys to the isolated attributes we need.
sub headers {

    my $msg = shift;


    my ($subject,$ip,$date,$from);
    my $loop = 0;
    my ($datere) = '\w{3}\,\s\d+\s\w{3}\s\d{4}\s\d{2}:\d{2}:\d{2}\s-\d{4}';
    my ($octet) = '([0-9]|[1-9][0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))';
    my ($ipre) = "$octet\.$octet\.$octet\.$octet";
    my ($skip_networks) = '207\.217\.120\.|207\.69\.200\.|10\.';

    foreach (@$msg) {

        /^$/ and last;
        /^X-MindSpring-Loop:/ and $loop = 1;

        unless ($subject) {
            /^Subject:\s*(.*)/i and $subject = $1;
        }

        #unless ($ip) {
        #		/\[($ipre)\]/o and do {
        #				 unless ($1 =~ /^$skip_networks/o) {
        #				 	$ip = $1;
        #				 };
        #		             }; # end do	
        #}
        unless ($ip) {
            /\[($ipre)\]/o and $ip = $1;
        }
        # snag the IP after X-MindSpring-Loop:	
        if (($loop) && (/\[($ipre)\]/o)) {
            $ip = $1;
            $loop = 0;
            #print "debug: setting ip to $ip\n";
        }

        unless ($date) {
            /($datere)/o and $date = $1;
            #$date and print "debug: $date\n";
        }

        unless ($from) {
            /^From:\s*(.*)/ and $from = $1;
        }


    } # end while

    !$ip and $ip = 'NULL';	
    !$subject and $subject = "$0:" . 'NULL';
    !$date and $date =  "$0:" . 'NULL';
    !$from and $from = "$0:" . 'NULL';

    return {
        "ip" => $ip,
        "subject" => $subject,
        "date" => $date,
        "from" => $from
    };

}

sub prevhour {
    my ($hour,$day,$mon,$year) = (localtime(time))[2,3,4,5];
    $year += 1900;
    $hour = sprintf("%02d",$hour);
    $day = sprintf("%02d",$day);
    $mon = sprintf("%02d",$mon + 1);


    my ($dir,$subdir); 
    if (($mon == '1') && ($day == 1) && ($hour == 0)){
        # roll back to december, decrement year
        $mon = '12';
        $day = '31';
        $hour = '23';
        $year = --$year;
        my $dir = $year . $mon . $day;
        return ($dir, $hour);
    }	elsif (	($day == '1') && ($hour == '0')) {
        $subdir = 23; 
        if ($mon == 2) {
            $dir = $year . '01' . '31';
        } elsif ($mon == 3) {
            $dir = $year . '02' . '28';
        } elsif ($mon == 4) {
            $dir = $year . '03' . '31';
        } elsif ($mon == 5) {
            $dir = $year . '04' . '30';
        } elsif ($mon == 6) {
            $dir = $year . '05' . '31';
        } elsif ($mon == 7) {
            $dir = $year . '06' . '30';
        } elsif ($mon == 8) {
            $dir = $year . '07' . '31';
        } elsif ($mon == 9) {
            $dir = $year . '08' . '31';
        } elsif ($mon == 10) {
            $dir = $year . '09' . '30';
        } elsif ($mon == 11) {
            $dir = $year . '10' . '31';
        } elsif ($mon == 12) {
            $dir = $year . '11' . '30';
        }
        return ($dir,$subdir);
    } elsif ($hour == 0) {
        --$day;
        $dir = $year . $mon . $day;
        $subdir = '23'; 
        return ($dir,$subdir);
    } else {
        --$hour;
        $dir = $year . $mon . $day;
        $subdir = $hour;
        return ($dir,$subdir);

    }

} # end sub


