#!/usr/bin/perl
use strict;
use warnings;

use File::Basename;
#######################################################
# remakelink removes the link and makes it again
# to point to the correct directory
# parameters: path, link
#######################################################
sub remakelink {
	my ($repopath, $link) = @_;
		unlink $link;
		my $rc = symlink $repopath, $link;
		# if link could not be made, die
		die "Could not link $link -> $repopath\n" unless $rc;

		# change ownership
		$rc = system("chown -h robert:robert $link");
		die "Could not change ownership of $link: $!\n" unless $rc == 0;
}
#######################################################	
# findrepo:
# if path to repo does not exist
# 	check if path is of form /mnt/device/svn|debhome
# 	if not die
# 	if it is a block device try and mount it
# 	else die
# 	now check if repo exists or die
# 	remake the link
# else 
# 	path found
#	remake the link
#end
#######################################################
sub findrepo {
	my ($repopath, $link) = @_;

	my ($rc, $device);

	# repo name is svn or debhome
	# repo path is /mnt/ad64/debhome or /mnt/ad64/svn
	my $reponame = basename($repopath);
	
	if ( ! -d $repopath) {
		# not found, check if path is a possible device
		# if path = /mnt/device/svn
		if ($repopath =~ m?/mnt/.*/$reponame?) {
			# path is of form /mnt/something/svn
			# is 'something a block device'
			$device = (split(/\//, $repopath))[2];
			$rc = system("blkid -L $device");
			if ($rc == 0) {
				# it is a block device
				# check if it is mounted,
				# if so die because repo not found
				$rc = system("findmnt --source LABEL=$device");
				die "Device $device is mounted and $reponame not found\n" if $rc == 0;
				
				# try and mount it
				# make the directory if it does not exist
				print "mounting $device at /mnt/$device\n";
				mkdir "/mnt/$device" unless -d "/mnt/$device";
				$rc = system("mount -v -L $device /mnt/$device");

				# die if it is not a block device
				die "Could not mount $device, $reponame not found: $!\n" unless $rc == 0;

				# check that svn is found
				# un mount if not
				unless ( -d $repopath) {
					# svn not found, umount device and die
					system("umount -v /mnt/$device");
					die "Could not find $reponame at $repopath\n";
				}

				# device is mounted, remake link
				remakelink $repopath, $link;

			} else {
				# device is not a block device
				# and svn not found, die
				die "$device is not a block device and $reponame was not found\n"
			}
		} else {
			# svn path is not of form /mnt/device/svn
			# so svn not found, die
			die "Could not find $reponame at $repopath\n";
		}
	} else {
		# the path does exist check the link
		remakelink $repopath, $link;
	}
	print "found $reponame at $repopath\n";
}

# test
findrepo("/mnt/trans/svn", "/mnt/svn");
