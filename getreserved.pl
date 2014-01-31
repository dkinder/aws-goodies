#!/usr/bin/env perl
# Written by David Kinder July 2013
# 
# This script will return a list of used and unused reservations. 
#
#TODO:
# Incorporate Perl Modules for AWS API
#
# ec2-api-tools-1.6.8.0
# perl v5.14.2

$ACCESS_KEY="ENTER YOUR EC2 ACCESS KEY  HERE";
$SECRET_KEY="ENTER YOUR EC2 SECRET KEY HERE";
`ec2-describe-instances -O $ACCESS_KEY -W $SECRET_KEY --show-empty-fields | grep INSTANCE | grep running | awk -F'\t' '{print \$2,"\t"\$6,"\t"\$10,"\t"\$12,"\t"\$19,"\t"\$26}' > ri0.txt`;
`ec2-describe-reserved-instances -O $ACCESS_KEY -W $SECRET_KEY --show-empty-fields --headers | grep RESERVEDINSTANCES | grep active | awk -F'\t' '{print \$3,"\t"\$4,"\t"\$5,"\t"\$9}'  > ri1.txt`;


open(RI0,"<ri0.txt");


while (<RI0>) {
  my ($id,$status,$type,$az,$vpc,$os) = split(/\t/,$_);
	chomp ($os, $id, $vpc, $az, $status);

	if ($vpc =~ /vpc/ ) { 
		$vpc = 'VPC' ;
	} else {
 		$vpc = 'NonVPC';
	}

	next if ( $status != "running " ) ;
	$instance{$az}->{$vpc}->{$os}->{$type} += 1;
}

close RI1;
open(RI1,"<ri1.txt");
while (<RI1>) {
	my ($az,$type,$os_vpc,$count) = split(/\t/,$_);
	my ($os, $vpc) = split('\(',$os_vpc);
	chomp ($os, $vpc, $az, $count);

	if ($vpc =~ /VPC/ ) { 
		$vpc = 'VPC' ;
	} else {
 		$vpc = 'NonVPC';
	}

	if ( $os =~ /Linux/ig ) {
		$os = "paravirtual";
	} else {
		$os = "hvm";
	}

	$instance2{$az}->{$vpc}->{$os}->{$type} += $count;
}

close RI1;

foreach $zone (sort keys %instance) {

	print "********************************************************************\n";
	print "$zone\n";
	%KEYS = getUniqueKeys(\$instance{$zone},\$instance2{$zone});
	foreach $cloud ( sort keys %KEYS ) {
		print "\t$cloud\n";
		%KEYS2 = getUniqueKeys(\$instance{$zone}{$cloud},\$instance2{$zone}{$cloud});
		foreach $op_sys ( sort keys %KEYS2 ) {
			print "\t\t$op_sys\n";
			%KEYS3 = getUniqueKeys( \$instance{$zone}{$cloud}{$op_sys}, \$instance2{$zone}{$cloud}{$op_sys} );
			foreach $ins_type ( sort keys %KEYS3 ) {
				print "\t\t\t$ins_type\t: ";
				$total_instances = $instance{$zone}{$cloud}{$op_sys}{$ins_type};
				$total_instances != NULL ? $total_instances : ( $total_instances = 0);
				$reserved_instances = $instance2{$zone}->{$cloud}->{$op_sys}->{$ins_type}; 
				$reserved_instances != NULL ? $reserved_instances : ( $reserved_instances = 0);

				#($not_used = $reserved_instances - $total_instances) > 0 ? $not_used_text = "*";$total_not_used += $not_used : ($not_used_text = '' );
				if (($not_used = $reserved_instances - $total_instances) > 0) {
					$not_used_text = "*";
					$total_not_used += $not_used;
				} else {
					$not_used_text = '';
				}
				print " $total_instances / $reserved_instances $not_used_text";
				print "\n";
			}
		}
	}

}
print "\nThere are $total_not_used reservations not used!\n\n";

sub getUniqueKeys() {
	my @hashes = @_;
	my %newhash;
	foreach  my $hash ( @hashes ){
		if ( $$hash =~ /hash/i ) {
			foreach  my $key ( keys $$hash ) {
				$newhash{$key} = 1;
			}
		}
	}
	return %newhash;
}
