#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;
use File::Basename;

# global constant links for debhome and subversion
# sources for macrium and recovery
my $svn = "/mnt/svn";
my $debhome = "/mnt/debhome";
my $macriumsource = "/root/MACRIUM";
my $recoverysource = "/root/RECOVERY";

# get command line arguments
our($opt_m, $opt_i, $opt_c, $opt_e, $opt_u, $opt_p, $opt_D, $opt_S, $opt_h, $opt_d, $opt_M, $opt_R, $opt_V);

#######################################################
# this script makes a live system on a partition
# called linux. This script will also partition
# and format a disk for the live system.
# partition 1: 1G fat32 for MACRIUM REFLECT
# partition 2: 8G (selectable) for linux live
# partition 3: rest of disk for ntfs label ele
#
# MACRIUM reflect can be installed on  partition 1
# before the live system is installed.
# command line parameters:
# makelive.pl -c ubuntu-mate iso nameand -u for upgrade and -p package list -d for partitioning disk -e for do chroot
#
# the disk
# partition 1 8G    [MACRIUM] fat32   contains macrium and ubuntu-mate, boots from grub uuid = AED6-434E
# partition 2 rest  [ele]     ntfs    contains backup files and sources for windows recovery, Lenovo and desktop
#
#######################################################



######################################################
# sub to delete all partitions and make a
# partition 1: 1G fat32 for MACRIUM REFLECT LABEL = MACRIUM uuid = AED6-434E
# partition 2: 8G (default - or selectable) fat32 for linux live LABEL = LINUXLIVE uuid = 3333-3333
# partition 3: 2G fat32 LABEL =  RECOVERALL uuid = 4444-4444
# partition 3: rest of disk ntfs LABEL = ele
# all data on the disk is deleted.
# the partitions are also formatted.
# parameters passed: partition size in GB
# sub aborts on any error
# requires: disk for MACRIUM to be attached, not mounted
######################################################
sub partitiondisk {
	# get size of first partition
	my $linuxlivesize = $_[0];

	# show devices attached
	print "######################################################\n";
	my $rc = system("lsblk -o PATH,TYPE,MODEL,LABEL,MOUNTPOINT");
	die "aborting: error from lsblk\n" unless $rc == 0;
	print "######################################################\n";

	# get the device
	print "\n\nenter device to be formatted: form /dev/sdX\n";

	my $device = <STDIN>;
	chomp($device);

	# show the device to check
	print "\n######################################################\n";
	$rc = system("parted -s $device print");
	die "aborting: error from parted\n" unless $rc == 0;
	print "######################################################\n";

	print "\n\nAll data on $device will be deleted: is this correct (yes|no)?\n";
	my $answer = <STDIN>;
	chomp($answer);

	if ($answer =~ /^yes$/i) {
		print "partitioning $device\n";

		# MACRIUM is 0 - 1GB
		# LINUXLIVE partition size is $partsize + 1GB for the MACRIUM partition"
		# RECOVERALL partition size is 2G after LINUXLIVE
		# ele partition is 100% after RECOVERALL
		my $macriumsize = 1;
		my $recoverallsize = 2;
		my $part1start = 0;
		my $part1end = $macriumsize;
		my $part2start = $part1end;
		my $part2end = $part2start + $linuxlivesize; 
		my $part3start = $part2end;
		my $part3end = $part3start + $recoverallsize;
		my $part4start = $part3end;
		my $part4end = "100%";

		# convert part start and end to XXGB string
		$part1start .= "GB";
		$part1end   .= "GB";
		$part2start .= "GB";
		$part2end   .= "GB";
		$part3start .= "GB";
		$part3end   .= "GB";
		$part4start .= "GB";
		
print "$part1start $part1end $part2start $part2end $part3start $part3end $part4start $part4end\n";
		# delete all partitions and make new ones
		$rc = system("parted -s --align optimal $device mktable msdos mkpart primary fat32 $part1start $part1end mkpart primary fat32 $part2start $part2end mkpart primary fat32 $part3start $part3end mkpart primary ntfs  $part4start $part4end set 1 boot on");
		die "aborting: error partitioning $device\n" unless $rc == 0;

		# format the first partition
		# the sleep is needed to let the disk settle
		# after partitioning. With no sleep formatting fails
		# if partition size is bigger than 12GB
		sleep 2;

		# format partition 1
		print "formatting partition " . $device . "1\n";
		$rc = system( "mkfs.vfat -v -n MACRIUM -i AED6434E " . $device . "1");
		die "aborting: error formatting " . $device . "1\n" unless $rc == 0;

		# format second partition
		print "formatting partition " . $device . "2\n";
		$rc = system("mkfs.vfat -v -n LINUXLIVE -i 33333333 " . $device . "2");
		die "aborting: error formatting " . $device . "2\n" unless $rc == 0;

		# format third partition
		print "formatting partition " . $device . "3\n";
		$rc = system("mkfs.vfat -v -n RECOVERALL -i 44444444 " . $device . "3");
		die "aborting: error formatting " . $device . "3\n" unless $rc == 0;

		# format forth partition
		print "formatting partition " . $device . "4\n";
		$rc = system("mkfs.ntfs -v -Q -L ele  " . $device . "4");
		die "aborting: error formatting " . $device . "4\n" unless $rc == 0;

	} else {
		print "$device was not partitioned\n";
	}
}


##############################################################################
# this sub operates on the list @ARGV
# all the switches in the ARGV list are checked to see if they have arguments
# if they do not have arguments, the default arguments are inserted into ARGV
# so that getopts will not fail.
# no parameters are passed and none are returned.
# requires: none
##############################################################################
sub defaultparameter {

	# hash supplying default arguments to switches
	# -b is for mounting bit locker drives
	# -v is for mounting vera containers
	# -u is for unmounting any drive
	# the default argument, if not given on the command line is all drives
	my %defparam = ( -c => "none",
			 -d => 8,
			 -M => "$macriumsource",
			 -R => "$recoverysource");

	# for each switch in the defparam hash find it's index and insert default arguments if necessary
	foreach my $switch (keys(%defparam)) {
		# find index of position of -*
		my $i = 0;
		foreach my $param (@ARGV) {
			# check for a -b and that it is not the last parameter
			if ($param eq $switch) {
				if ($i < $#ARGV) {
					# -* has been found at $ARGV[$i] and it is not the last parameter
					# if the next parameter is a switch -something
					# then -* has no arguments
					# check if next parameter is a switch
					if ($ARGV[$i+1] =~ /^-/) {
						# -* is followed by a switch and is not the last switch
						# insert the 2 default filenames as a string at index $i+1
						my $index = $i + 1;
						splice @ARGV, $index, 0, $defparam{$switch};
					}
				} else {
					# the switch is the last in the list so def arguments must be appended
					my $index = $i + 1;
					splice @ARGV, $index, 0, $defparam{$switch}; 
				}
			}
			# increment index counter
			$i++;
		}
	}
} 
####################################################
# sub to make filesystem.squashfs.
# dochroot must have been done
# filesystem.squashfs is written to chroot1/dochroot
# not All directories under /mnt must be empty
# no devices should be mounted
# parameters: chroot directory
# requires: none
####################################################
sub makefs {
	my $chroot_dir = $_[0];
	
	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";

	# if the file exists, delete it
	# or mksquashfs will fail.
	unlink "$chroot_dir/dochroot/filesystem.squashfs";
	
	# make the file system the boot directory must be included, config-xxxx file is needed by initramfs during install
	my $rc = system("mksquashfs " . $chroot_dir . " $chroot_dir/dochroot/filesystem.squashfs -e oldboot -e dochroot -e upgrade -e packages -e isoimage");
	die "mksquashfs returned and error\n" unless $rc == 0;
}
######################################################
# sub to edit grub default and set the theme in the filesystem.squashfs
# parameters: chroot dir
# requires: no devices to be mounted
######################################################
sub editgrub {
	my $chroot_dir = $_[0];
	
	# set /etc/default/grub, GRUB-CMDLINE_LINUX_DEFAULT=""
	system("sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' $chroot_dir/etc/default/grub");
	# set colours
	system("sed -i -e 's/menu_color_normal=.*/menu_color_normal=white\\/blue\"/' -e 's/menu_color_highlight=.*/menu_color_highlight=yellow\\/black\"/' $chroot_dir/etc/grub.d/05_debian_theme");

}

#######################################################
# sub to get codename from the cdrom
# the name is in /mnt/cdrom/dists   impish
# which is a directory.
# the cdrom must be mounted
# and the codename is returned if found
# else undefined is returned.
# no parameters are passed to this sub.
# requires: cdrom to be mounted
#######################################################
sub getcodename {
	# open directory for reading
	opendir DIR, "/mnt/cdrom/dists" or die "Could not open /mnt/cdrom/dists: $!\n";
        my ($dir, $codename);
	undef $codename;
	
        # search for the correct name, list contains . .. impish stable unstable
        while ($dir = readdir(DIR)) {
        	# if dir is a . or .. ignore it
        	if ($dir =~ /^\./) {
        		next;
        	} else {
        		# check if dir is a link or not
        		if ( ! -l "/mnt/cdrom/dists/$dir") {
        			# code name found
        			$codename = $dir;
        			last;
        		}
        	}
        }
        closedir DIR;

        return $codename;
}

#######################################################
# sub to bind sys tmp dev dev/pts proc for chroot
# environment
# access to debhome and svn in the chroot environment
# is done through the binding of /mnt/debhome to /chroot/mnt/debhome
# and for svn /mnt/svn to /chroot/mnt/svn
# the directories are made in by bindall in the
# chroot environment
# usage: bindall chroot_dir
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
sub bindall {
	# parameters
	my $chroot_dir = $_[0];
	chdir $chroot_dir or die "$chroot_dir does not exist, exiting\n";

	# bind all in list
	# bind for all in list
	my @bindlist = ("/proc", "/dev", "/dev/pts", "/sys", "/tmp", "$svn", "$debhome");
	my $rc;

	# make directories for debhome and svn
	mkdir "$chroot_dir" . "$svn" unless -d "$chroot_dir" . "$svn";
	mkdir "$chroot_dir" . "$debhome" unless -d "$chroot_dir" . "$debhome";
	
	foreach my $dir (@bindlist) {
		# check if it is already mounted
		$rc = system("findmnt $chroot_dir" . "$dir 2>&1 >/dev/null");
		unless ($rc == 0) {
			# not mounted, mount dir
			$rc = system("mount --bind $dir $chroot_dir" . "$dir");
			die "Could not bind $chroot_dir" . "$dir: $!\n" unless $rc == 0;
			print "$chroot_dir" . "$dir mounted\n";
		} else {
			# already mounted
			print "$chroot_dir" . "$dir is already mounted\n";
		}
	}
}

#######################################################
# sub to unbind sys tmp dev dev/pts proc for chroot
# environment
# usage: unbindall chroot_dir
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
sub unbindall {
	# parameters
	my $chroot_dir = $_[0];
	die "$chroot_dir does not exist, exiting\n" unless -d $chroot_dir;

	# bind for all in list
	my @bindlist = ("/proc", "/dev/pts", "/dev", "/sys", "/tmp", "$svn", "$debhome");
	my $rc;
	foreach my $dir (@bindlist) {
		$rc = system("findmnt $chroot_dir" . "$dir 2>&1 >/dev/null");
		if ($rc == 0) {
			# dir mounted, unmount it
			print "$chroot_dir" . "$dir unmounted\n";
			$rc = system("umount $chroot_dir" . "$dir");
			die "Could not umount $chroot_dir" . "$dir: $!\n" unless $rc == 0;
		} else {
			# dir not mounted
			print "$chroot_dir" . "$dir not mounted\n";
		}
	}
}
	
#################################################
# this sub sets up sources.list and debhome.list
# in chroot_dir/etc/apt and chroot_dir/etc/apt/sources.list.d
# The call setaptsources (codename, chroot_dir)
# requires: svn
#################################################
sub setaptsources {
	my ($codename, $chroot_dir) = @_;
	my $rc;
	# create sources.list
	open (SOURCES, ">", "$chroot_dir/etc/apt/sources.list");
	print SOURCES "deb http://archive.ubuntu.com/ubuntu $codename main restricted multiverse universe
	deb http://archive.ubuntu.com/ubuntu $codename-security main restricted multiverse universe
	deb http://archive.ubuntu.com/ubuntu $codename-updates  main restricted multiverse universe
	deb http://archive.ubuntu.com/ubuntu $codename-proposed  main restricted multiverse universe\n";
	close SOURCES;

	# debhome.sources and debhomepubkey.asc are installed from liveinstall package now.
	# extract debhome.sources from  subversion to /etc/apt/sources.list.d/debhome.sources
	do 
	{
		$rc = system("svn export --force file://$svn/root/my-linux/sources/amd64/debhome.sources  " . $chroot_dir . "/etc/apt/sources.list.d/");
		die "Could not export debhome.sources from svn\n" unless $rc == 0;
	} unless ( -f $chroot_dir . "/etc/apt/sources.list.d/debhome.sources");

	# get the public key for debhome
	# make the /etc/apt/keyrings directory if it does not exist
	mkdir "/etc/apt/keyrings" unless -d "/etc/apt/keyrings";
	
	do 
	{
		$rc = system("svn export --force file://$svn/root/my-linux/sources/gpg/debhomepubkey.asc  " . $chroot_dir . "/etc/apt/keyrings/");
		die "Could not export debhomepubkey.asc from svn\n" unless $rc == 0;
	} unless (-f $chroot_dir . "/etc/apt/keyrings/debhomepubkey.asc");	

}
############################################################
# umount the cdrom.
# sometimes it is still busy.
# needs some time ater use to umount
############################################################
sub umountcdrom {
	# un mount /mnt/cdrom
	my $rc = system("findmnt /mnt/cdrom");
	system("umount -d -v -f /mnt/cdrom") if $rc == 0;
}

############################################################
# sub to mount cdrom
# un mounts anything on /mnt/cdrom
# then mounts cdrom at /mnt/cdrom
# fstab edited so debhomedev can be mounted
# debhomedev directory made
# links /mnt/debhome and /mnt/svn are made
# parameters to pass: iso-name
############################################################
sub mountcdrom {
	my $isoimage = $_[0];
	my $rc;

	# if /mnt/cdrom exists, unmount iso image if it is mounted
	# mount ubuntu-mate iso image
	if (-d "/mnt/cdrom") {
		print "checking if cdrom is mounted\n";
		$rc = system("findmnt /mnt/cdrom");

		# umount /mnt/cdrom
		system("umount -v /mnt/cdrom") if $rc == 0;
	} else {
		# /mnt/cdrom does not exist, create it
		mkdir "/mnt/cdrom";
	}

	$rc = system("mount -o ro,loop " . $isoimage . " /mnt/cdrom");
	die "Could not mount $isoimage\n" unless $rc == 0;
}

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
# parameters: repopath, $link  (/mnt/svn or /mnt/debhome)
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

##################################################################
# sub to set up new chroot environment.
# the environment is copied from the cdrom
# makes the links /mnt/debhome and /mnt/svn in the chroot environment
# parameters passed: chroot_directory, isoimage
# requires: mountcdrom to be mounted
####################################################################
sub createchroot {
	# creating new chroot environment
	my ($chroot_dir, $isoimage) = @_;
	my $rc;
		
	# delete the old chroot environment if it exists
	if (-d $chroot_dir) {
		unbindall $chroot_dir;
		# check if $chroot_dir/boot is mounted in chroot environment
		# need to protect the live drive
		# incase the binds are still active
		$rc = system("findmnt $chroot_dir/boot");
		if ($rc == 0) {
			# un mount drive
			$rc = system("umount -v -f $chroot_dir/boot");
			die "Could not umount $chroot_dir/boot\n" unless $rc == 0;
		}

		# move it to /tmp/junk
		$rc = system("mv -f $chroot_dir  /tmp/junk");
		die "Could not move $chroot_dir to /tmp/junk" unless $rc == 0;
		
		# remove directory
		$rc = system("rm -rf /tmp/junk");
		die "cannot remove $chroot_dir\n" unless $rc == 0;
		print "removed /tmp/junk\n";
	}

	#####################################################################################
	# copy and edit files to chroot
	#####################################################################################
	# mount the cdrom
	mountcdrom $isoimage;
	
	# unsquash filesystem.squashfs to the chroot directory
	# the chroot_dir directory must not exist
	$rc = system("unsquashfs -d " . $chroot_dir . " /mnt/cdrom/casper/filesystem.squashfs");
	die "Error unsquashing /mnt/cdrom/casper/filesystem.squashfs\n"unless $rc == 0;
	print "unsquashed filesystem.squashfs\n";
		
	# edit fstab in chroot so debhome can be mounted
	#chdir $chroot_dir . "/etc";
	#system("sed -i -e '/LABEL=$debhomedev/d' fstab");
	#system("sed -i -e 'a \ LABEL=$debhomedev /mnt/$debhomedev ext4 defaults,noauto 0 0' fstab");

	# make directory for debhomedev to be mounted in the chroot environment
	#mkdir "$chroot_dir/mnt/$debhomedev" unless -d "$chroot_dir/mnt/$debhomedev";

	# make the link for /mnt/debhome -> /chroot_dir/mnt/$debhomedev in the chroot environment
	#$rc = system("chroot $chroot_dir ln -s /mnt/$debhomedev/debhome $debhome");
	#die "Error making debhome link: $!" unless $rc == 0;

	# make the link for /mnt/svn -> /chroot_dir/$svnpath in the chroot environment
	#$rc = system("chroot $chroot_dir ln -s $svnpath $svn");
	#die "Could not make link $svn -> $svnpath: $!" unless $rc == 0;

	# copy resolv.conf and interfaces so network will work
	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	system("cp /etc/network/interfaces " . $chroot_dir . "/etc/network/");

	system("cp -dR /etc/apt/trusted.gpg.d " . $chroot_dir . "/etc/apt/");
	system("cp -a /etc/apt/trusted.gpg " . $chroot_dir . "/etc/apt/") if -f "/etc/apt/trusted.gpg";

	# save the name of the iso in $chroot_dir/isoimage/isoimage.txt
	mkdir "$chroot_dir/isoimage";
	open ISO, ">", "$chroot_dir/isoimage/isoimage.txt" or die "could not save iso image name: $!\n";
	print ISO "$isoimage";
	close ISO;

	# get the code name
	my $codename = getcodename();
	# write it to a file $chroot_dir/isoimage/codename.txt
	open CDN, ">", "$chroot_dir/isoimage/codename.txt" or die "could not write code name to $chroot_dir/isoimage/codename.txt: $!\n";
	print CDN "$codename";
	close CDN;

	# copy vmlinuz and initrd from cdrom to
	# $chroot_dir/oldboot incase there is no
	# upgrade for the kernel. If there was 
	# an upgrade by liveinstall the new
	# vmlinuz and initrd will be copied over
	# the original ones.
	mkdir "$chroot_dir/oldboot" or die "could not make $chroot_dir/oldboot: $!\n";
	system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd $chroot_dir/oldboot");
	
	# copy pool and install files for ubuntu mate
	# to a temp directory $chroot_dir/isoimage
	chdir "/mnt/cdrom";
	$rc = system("cp -dR .disk dists install pool preseed " . $chroot_dir . "/isoimage/");
	die "could not copy dists install pool preseed to $chroot_dir/isoimage: $!\n" unless $rc == 0;

	# umount cdrom
	chdir "/root";
	umountcdrom;
}

###############################################
# sub to change root  and run liveinstall.sh
# makes a dir dochroot to indicate dochroot was run
# also deletes filesystem.squashfs in docchroot
# since it will now change.
# debhome and svn are accessed from the chroot environment
# by binding /mnt/debhome and /mnt/svn to /mnt/debhome and /mnt/svn
# in the chroot environment
# installfs will use filesystem.squashfs if it exists
# also requires svn if packages and or upgrade are done.
# parameters: chroot_directory, upgrade, packages_list
# requires: /mnt/debhome and /mnt/svn to be binded to debhome and svn
###############################################
sub dochroot {
	my ($chroot_dir, $upgrade, $packages) = @_;

	# get codename
	open CDN, "<", "$chroot_dir/isoimage/codename.txt" or die "could not open $chroot_dir/isoimage/codename.txt: $!\n";
	my $codename = <CDN>;
	chomp($codename);
	close CDN;
	print "code name is: $codename\n";


	# generate chroot_dir/etc/apt/sources.list
	# and chroot_dir/etc/sources.list.d/debhome.list
	setaptsources ($codename, $chroot_dir);

	# copy xwindows themes and icons to /usr/share
	# if themes.tar.xz and icons.tar.xz are found
	my $rc;
	if (-f "$debhome/xconfig/themes.tar.xz") {
		$rc = system("tar --xz -xf $debhome/xconfig/themes.tar.xz -C $chroot_dir/usr/share");
		die "Could not extract themes from $debhome/themes.tar.xz" unless $rc == 0;
	}

	# if themes.tar.xz and icons.tar.xz are found
	if (-f "$debhome/xconfig/icons.tar.xz") {
		$rc = system("tar --xz -xf $debhome/xconfig/icons.tar.xz -C $chroot_dir/usr/share");
		die "Could not extract themes from $debhome/xconfig/icons.tar.xz" unless $rc == 0;
	}
	
	#############################################################################################
	# enter the chroot environment
	#############################################################################################

	# install apps in the chroot environment
	bindall $chroot_dir;

	# chroot/mnt/debhome and /chroot/mnt/svn are bound to /mnt/debhome and /mnt/svn
	# mount debhome in the chroot environment
	#$rc = system("chroot $chroot_dir mount -r -L $debhomedev /mnt/$debhomedev");
	#die "Could not mount $debhomedev in chroot environment: $!\n" unless $rc == 0;
	
	# parameters must be quoted for Bash
	# liveinstall.sh "-u "upgrade/noupgrade" -p "package list"
	# make parameters list for liveinstall.sh
	# parameters is set to " " so that if only packages is given
	# there won't be a warning.
	my $parameters = " ";
	$parameters = "-u " if $upgrade;
	$parameters = $parameters . "-p " . $packages if $packages;
	
	# execute liveinstall.sh in the chroot environment
	print "parameters: $parameters\n" if $parameters;

	# liveinstall is a package in the dehome distribution
	# so debhome must be setup for liveinstall to be
	# installed
	# do an update and install liveinstall
	$rc = system("chroot $chroot_dir apt update");
	die "Could not apt update in chroot environment $!\n" unless $rc == 0;
	$rc = system("chroot $chroot_dir apt install -y liveinstall");
	die "Could not install liveinstall in chroot environment $!\n" unless $rc == 0;

	# now execute liveinstall and check the return
	my $lirc = system("chroot $chroot_dir liveinstall.sh $parameters");
	
	#*********************** TBD ************************
	#####################################################
	
	# umount debhome in the chroot environment
	#$rc = system("chroot $chroot_dir umount /mnt/$debhomedev");
	#die "Could not umount $debhomedev in chroot environment: $!\n" unless $rc == 0;
	
	# for exiting the chroot environment
	# unbind debhome and svn
	unbindall $chroot_dir;

	# check if liveinstall exited with error in chroot environment
	die "liveinstall.sh exited with error" unless $lirc == 0;
	# liveinstall.sh will create directory dochroot
	# to indicate chroot was done.
	# filesystem.squashfs must be deleted in /dochroot
	# because the filesystem will have changed.
}

#######################################################
# this sub determines the version
# which will be used for grub
# the full iso name is in $chroot_dir/isoimage/isomage.txt
# parameter passed: $chroot_dir
# requirements: none
######################################################
sub getversion {
	my $chroot_dir = $_[0];
	
	################################
	# determine the version for grub
	# get the iso name from $chroot_dir/isoimage/isoimage.txt
	################################

	# read the file 
	open ISO, "<", "$chroot_dir/isoimage/isoimage.txt" or die "could not open $chroot_dir/isoimage/isoimage.txt: $!\n";
	my $isoimage = <ISO>;
	chomp($isoimage);
	close ISO;
	
	# get version
	# names could be ubuntu-21.04-desktop-amd64.iso
	# or             /some/path-with/extra/ubuntu-mate-21.04-desktop-amd64.iso
	# the file name must be striped from the path
	my $file = basename($isoimage);
		
	my $version = (split /-/, $file)[1];
	print "first try: linux version = $version\n";

	# check if version is a digit
	if ($version !~ /^(\d+)/) {
		# not a digit, must be the next field
		$version = (split /-/, $file)[2];
		print "linux version = $version\n";
				
		# if still not a version, prompt for version
		if ($version !~ /^\d+/) {
			# still not a digit, prompt
			print "Can't determine version, enter version\n";
			$version = <STDIN>;
			chomp($version);
		}
	}
	return $version;
}

#################################################
# install macrium files to MACRIUM/RECOVERALL/SOURCES (ele)
# the files are copied to the respective partition
# parameter: full path to source files, partition label, target root directory
# the source directory is not created
#################################################
sub installfiles {
	my $source = shift @_;
	my $label = shift @_;
	my $rootdir = shift @_;
	
	# mount the parition
	mkdir "/mnt/$label" unless -d "/mnt/$label";
	my $rc = system("mount -L $label /mnt/$label");
	die "Could not mount $label: $!\n" unless $rc == 0;

	# copy the files
	# make target directory if it does not exist
	mkdir "/mnt/$label" . "$rootdir" unless -d "/mnt/$label" . "$rootdir";
	$rc = system("cp -dRv -T $source /mnt/$label" . "$rootdir");
	die "Could not copy $source to /mnt/$label" . "$rootdir: $!\n" unless $rc == 0;

	#un mount the drive
	$rc = system("umount /mnt/$label");
	die "Could not umount $label: $!\n" unless $rc == 0;
}
	
#################################################
# this sub sets up grub and installs it.
# this is only necessary for partition 1
# the call: installgrub(chroot_directory, partition_path)
# requires: svn and LINUXLIVE
#################################################
sub installgrub {
	
	##########################################################################################################
	# export the grub.cfg for mbr and uefi and edit grub only for partition 1
	##########################################################################################################
	my ($chroot_dir, $partition_path) = @_;
	my $rc;

	# export grub
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/mbr/ " . $chroot_dir . "/boot/grub/");
	die "Could not export mbr grub\n" unless $rc == 0;
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/efi/ " . $chroot_dir . "/boot/EFI/grub/");
	die "Could not export efi grub\n" unless $rc == 0;
	
	# now edit grub.cfg with the new version no.
	# edit mbr grub and set version
	# get version
	my $version = getversion($chroot_dir);
    
	chdir $chroot_dir . "/boot/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");
	chdir $chroot_dir . "/boot/EFI/grub";
	system("sed -i -e 's/ubuntu-version/$version/' grub.cfg");

	# this doesn't seem necessary from MACRIUM version 7.3
	# rename macrium file to stop only macrium_pe booting
	#system("mv " . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi "
	#             . $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi.old")
	#             if -e $chroot_dir . "/boot/EFI/Microsoft/Boot/bootmgfw.efi";

	# install grub
	# get device from partition path
	my $device = $partition_path;
	# partition_path is a partion device: eg /dev/sda1

	# remove last char to get the device path eg: /dev/sda
	chop $device;
	print "$device\n";
	system("grub-install --no-floppy --boot-directory=" . $chroot_dir . "/boot --target=i386-pc " . $device);
	
	system(" grub-install --no-floppy --boot-directory=" . $chroot_dir . "/boot/EFI --efi-directory="  . $chroot_dir . "/boot --removable --target=x86_64-efi " . $device);
}

####################################################
# sub to build filesystem.squashfs, copy dists, install
# pool preseed to /boot on drive.
# install and edit grub
# create the writable file for persistence
# and copy to casper
# uses filesystem.squashfs if it exists in dochroot
# else it builds if from scratch.
# this speeds up the process of install if filesystem.squashfs has not changed
# requires LINUXLIVE and svn to be mounted
####################################################
sub installfs {
	# parameters
	my ($label, $casper, $chroot_dir) = @_;
	
	# check if chroot environment exists
	die "$chroot_dir does not exist\n" unless -d $chroot_dir;

	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";
	
	# check LINUXLIVE is attached
	my $rc = system("blkid -L " . $label . " > /dev/null");
	die "$label is not attached\n" unless $rc == 0;
	
	# get partition_path of partition LINUXLIVE/UBUNTU ex: /dev/sda1
	my $partition_path = `blkid -L $label`;
	chomp $partition_path;
	print $label . " is: $partition_path\n";
	
	# check if the partition, LINUXLIVE  is mounted at any location
	# un mount it if it is mounted
	my $devandmtpt = `grep "$partition_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($devandmtpt);
	my ($dev, $mtpt) = split /\s+/, $devandmtpt;

	# if label LINUXLIVE|UBUNTU is mounted, un mount it
	if (defined $mtpt) {
		print "$label mounted at: $mtpt\n";
		$rc = system("umount $mtpt");
		die "$label cannot be unmounted\n" unless $rc == 0;
	}

	#############################################################################################
	# copy and edit files to chroot/boot
	#############################################################################################
	# if there is a filesystem.squashfs in dochroot
	# use it. If it does not exist it must be created
	# sub dochroot deletes it since filesystem.squashfs
	# would change if dochroot is invoked.
	makefs($chroot_dir) unless -f "$chroot_dir/dochroot/filesystem.squashfs";

	# empty /chroot1/boot
	# this must be done after makefs, the config-xxxx-generic file
	# must be in the filesystem.squashfs for initramfs to work
	# during linux installation
	chdir $chroot_dir . "/boot";
	system ("rm -rf *");

	# mount the partition LINUXLIVE/UBUNTU under 
	# chroot/boot, it was unmounted before chroot
	$rc = system("mount -L " . $label . " " . $chroot_dir . "/boot");
	die "Could not mount $label at $chroot_dir/boot\n" unless $rc == 0;
	
	# make casper dir if it does not exist
	if ( -d $casper) {
		# clean directory
		system("rm -rf $casper");
	}
	# create directory
	mkdir $casper;
	
	# createchroot now makes $chroot_dir/oldboot and
	# copies vmlinuz and initrd from the cdrom to oldboot.
	# if an upgrade of the kernel was done liveinstall
	# will have copied the newer vmlinuz and initrd to oldboot
	# should have done this originally.
	# vmlinuz and initrd must be copied to casper
	$rc = system("cp -fv $chroot_dir/oldboot/initrd $casper");
	die "Could not copy initrd\n" unless $rc == 0;
	$rc = system("cp -fv $chroot_dir/oldboot/vmlinuz $casper");
	die "Could not copy vmlinuz\n" unless $rc == 0;
	# do not delete oldboot, incase chroot1 is used again

	# delete ubuntu install files in chroot/boot
	chdir $chroot_dir . "/boot";
	system("rm -rf .disk dists install pool preseed grub");
	
	# copy pool and install files for ubuntu mate
	chdir "$chroot_dir/isoimage";
	system("cp -dR .disk dists install pool preseed " . $chroot_dir . "/boot/");
	
	# make a boot directory on LINUXLIVE
	# so that there is no error message from grub
	# at boot time that no /boot/ found.
	mkdir $chroot_dir . "/boot/boot";
		
	# setup and install grub if this is the first partition
	installgrub($chroot_dir, $partition_path);
	
	# set grub colours
	editgrub($chroot_dir);
	
	# make the persistence file
	chdir $casper;
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");

	# so chroot1/boot can be unmounted
	chdir "/root";
	
	
	$rc = system("cp -vf $chroot_dir/dochroot/filesystem.squashfs " . $casper);
	die "Could not move /tmp/filesystem.squashfs to $casper\n" unless $rc == 0;
	
	# umount chroot boot
	system("umount " . $chroot_dir . "/boot");
	$rc = system("findmnt " . $chroot_dir . "/boot");
	print "count not umount " . $chroot_dir . "/boot\n" if $rc == 0;
}

####################################################
# sub to initialise the setup of the LINUXLIVE partition.
# if -c given create new chroot from scratch or use existing one
# parameters passed:
# createchroot, ubuntuiso-name, upgrade, debhome path, svn full path, packages list)
####################################################
sub initialise {
	my ($doinstall, $makefs, $isoimage, $upgrade, $dochroot, $debhomepath, $svnpath, $packages)  = @_;

	# set up chroot dir
	my $chroot_dir = "/chroot";
	
	# die if no /choot and it is not being created
	if (! -d $chroot_dir) {
		die "chroot environment does not exist\n" unless $isoimage;
	}
	
	# some short cuts depending on the parition number
	my $casper = $chroot_dir . "/boot/casper";
	my $label = "LINUXLIVE";
		
	# if p or u given then set chrootuse
	# if chroot does not exist then set chroot
	print "packages: $packages\n" if $packages;
	print "upgrade:\n" if $upgrade;
	
	# if creating new chroot
	# un mount debhomedev
	#==============================================
	# determine how to umount debhome and svn
	# before creating chroot
	# debhome and svn are bound to directories in chroot
	# they are not bound at startup.
	# nothing to do here
	#==============================================

	createchroot($chroot_dir, $isoimage) if $isoimage;

	# -i needs svn and linuxlive
	# -u -p -e need svn and debhome
	# -c needs cdrom
	# -m needs nothing

	if ($upgrade or $packages or $dochroot) {
		# svn and debhome needed
		findrepo($svnpath, $svn);
		# now find debhome
		findrepo($debhomepath, $debhome);
		
	} elsif ($doinstall) {
		# only -i was given, only svn and linuxlive are required
		# check that subversion is accessible
		# if subversion is not accessible try and mount it if it is a device
		# if subversion is not found die
		findrepo($svnpath, $svn);
	} # end of elsif ($doinstall)
	

	# if packages or upgrade defined dochroot must be done
	if ($packages or $upgrade or $dochroot) {
		# if chroot environment does not exist die
		die ("chroot environment does not exist\n") unless -d $chroot_dir;
		# dochroot must be done
		dochroot($chroot_dir, $upgrade, $packages);
		
	} elsif (($doinstall or $makefs) and (! -d "$chroot_dir/dochroot")) {
		# dochroot must be done if directory dochroot does not exist
		dochroot($chroot_dir, $upgrade, $packages);
	}
	
	
	# make filesystem.squashfs if not installing
	makefs($chroot_dir) if $makefs;

	# install MACRIUM to partition 1
	# and RECOVERALL to partition 3 if -M and/or -R are given
	# source files are as follows
	# MACRIUM default /root/MACRIUM
	# RECOVERALL default /root/RECOVERY/RECOVERALL
	# SOURCE FILES for recovery /root/RECOVERY/SOURCES
	# recovery source must contain RECOVERALL for (RECOVERALL) and SOURCES (for ele/sources)
	installfiles($opt_M, "MACRIUM", "/") if $opt_M;

	# for recovery files
	do {
		installfiles("$opt_R/RECOVERALL", "RECOVERALL", "/");
		installfiles("$opt_R/SOURCES", "ele", "/sources");
	} if $opt_R;

	# install in LINUXLIVE/UBUNTU
	installfs($label, $casper, $chroot_dir) if $doinstall;

}

sub usage {
	my ($debhomepath, $svnpath) = @_;
	print "-c iso name, create changeroot -- needs iso image\n";
	print "-u do a full-upgrade -- needs svn debhome\n";
	print "-e run dochroot -- needs svn debhome\n";
	print "-m make filesystem.squashfs, dochroot must be complete -- needs nothing\n";
	print "-p list of packages to install quotes -- needs svn debhome\n";
	print "-D full path for debhome, default is $debhomepath\n";
	print "-S full path to subversion, default is $svnpath\n";
	print "-d size of partition in GB the disk into an 8G(default) fat32 LINUXLIVE plus the reset ntfs ele\n -- ";
	print "-i install the image to LINUXLIVE\n";
	print "-M fullsource of macrium files, default is $macriumsource\n";
	print "-R full source of recovery, contains RECOVERALL and SOURCES dirs, default is $recoverysource\n";
	print "-V check version and exit\n";
	exit 0;
}
##################
# Main entry point
##################

# command line parameters
# -c ubuntu-mate iso name or none (default)
# -p "package list of extra packages
# -u upgrade or not
# -l disk label of debhome
# -s full path to subersion
# -d optional size in GB of partition
# One or both iso's can be given.
# package list in quotes, if given

# -i needs svn and linuxlive
# -u -p -e need svn and debhome
# -c needs cdrom
# -m needs nothing

# default paths for debhome and svn
my $debhomepath = "/mnt/ad64/debhome";
my $svnpath = "/mnt/ad64/svn";

# get command line options

# default parameters for -d default is 8GB
defaultparameter();

getopts('mic:ep:huS:d:M:R:VD:');

# check version and exit 
if ($opt_V) {
	system("dpkg-query -W makelive");
	exit 0;
}

# setup debhome if it has changed from the default
$debhomepath = $opt_D if $opt_D;

# setup svn path if it has changed
# done here for usage sub
# svnpath overrides previous path
# if it has changed
$svnpath = $opt_S if $opt_S;

usage($debhomepath, $svnpath) if $opt_h;
# return code from functions
my $rc;

# check for packages and upgrade
# package list must be in quotes
my $packages = "\"" . $opt_p . "\"" if $opt_p;

# check if iso exists
if ($opt_c) {
	# check iso image exists
	die "iso image $opt_c does not exist\n" unless ((-f $opt_c) or ("$opt_c" eq "none"));
}

# if the -d option is given
# partition the disk imediately
# so the questions can be answered
# at the begining
# $opt_d is the size of GB of the partition

partitiondisk($opt_d) if $opt_d;

# initialise variables and invoke subs depending on cmdine parameters
initialise($opt_i, $opt_m, $opt_c, $opt_u, $opt_e, $debhomepath, $svnpath, $packages);
