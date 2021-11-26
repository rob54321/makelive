#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;

#######################################################
# this script makes a live system on MACRIUM and UBUNTU paritions
# Macrium Reflect 7 must have been installed into partition 1.
#
#
# command line parameters:
# makelive.pl -1 ubuntu-mate iso name | -2 ubuntu iso name and -u for upgrade and -p package list
#
# the disk
# partition 1 [MACRIUM] fat32   contains macrium and ubuntu-mate, boots from grub
# partition 2 [UBUNTU]  fat32   contains ubuntu
# partition 3 [ssd]     ntfs    contains backup files
#
#######################################################

# sub to edit grub default and set the theme in the filesystem.squashfs
sub setgrub {
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
        close DIR;

        return $codename;
}

#######################################################
# sub to bind sys tmp dev dev/pts proc for chroot
# environment
# usage: bindall chroot_dir
# returns: none
# exceptions: dies if chroot dir does not exist
#######################################################
sub bindall {
	# parameters
	my $chroot_dir = $_[0];
	chdir $chroot_dir or die "$chroot_dir does not exist, exiting\n";

	# bind
	system("mount --bind /proc proc");
	system("mount --bind /tmp tmp");
	system("mount --bind /dev dev");
	system("mount --bind /dev/pts dev/pts");
	system("mount --bind /sys sys");
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

	# bind
	system("umount $chroot_dir/proc");
	system("umount $chroot_dir/dev/pts");
	system("umount $chroot_dir/dev");
	system("umount $chroot_dir/sys");
	system("umount $chroot_dir/tmp");
}
	
#######################################################
# this sub determines the version
# which will be used for grub
# parameters passed: getversion(full-path-to-iso)
######################################################
sub getversion {
	################################
	# determine the version for grub
	################################
	my $ubuntuiso = shift;

	# get version
	# names could be ubuntu-21.04-desktop-amd64.iso
	# or             ubuntu-mate-21.04-desktop-amd64.iso
	
	my $version = (split /-/, $ubuntuiso)[1];

	# check if version is a digit
	if ($version !~ /^(\d+)/) {
		# not a digit, must be the next field
		$version = (split /-/, $ubuntuiso)[2];
		
		# if still not a version, prompt for version
		if ($version !~ /^\d+/) {
			# still not a digit, prompt
			print "Can't determine version, enter version\n";
			$version = <STDIN>;
		}
	}
	return $version;
}
#################################################
# this sub sets up sources.list and debhome.list
# in chroot_dir/etc/apt and chroot_dir/etc/apt/sources.list.d
# The call setaptsources (codename, chroot_dir)
#################################################
sub setaptsources {
	my ($codename, $chroot_dir) = @_;
	# create sources.list
	open (SOURCES, ">", "$chroot_dir/etc/apt/sources.list");
	print SOURCES "deb http://archive.ubuntu.com/ubuntu $codename main restricted multiverse universe
deb http://archive.ubuntu.com/ubuntu $codename-security main restricted multiverse universe
deb http://archive.ubuntu.com/ubuntu $codename-updates  main restricted multiverse universe
deb http://archive.ubuntu.com/ubuntu $codename-proposed  main restricted multiverse universe\n";
	close SOURCES;

	# create debhome.list
	open (DEBHOME, ">", "$chroot_dir/etc/apt/sources.list.d/debhome.list");
	print DEBHOME "deb file:///mnt/debhome home main\n";
	close DEBHOME;
}

# this sub sets up grub and installs it.
# this is only necessary for partition 1
# the call: grubsetup(ubuntu_iso_name, chroot_directory, partition_path, subversion path)
#################################################
sub grubsetup {
	
	##########################################################################################################
	# export the grub.cfg for mbr and uefi and edit grub only for partition 1
	##########################################################################################################
	my ($ubuntuiso, $chroot_dir, $partition_path, $svn) = @_;
	my $rc;

	# export grub
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/mbr/ " . $chroot_dir . "/boot/grub/");
	die "Could not export mbr grub\n" unless $rc == 0;
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts/grub/vfat/efi/ " . $chroot_dir . "/boot/EFI/grub/");
	die "Could not export efi grub\n" unless $rc == 0;
	
	# now edit grub.cfg with the new version no.
	# edit mbr grub and set version
	# get version
	my $version = getversion($ubuntuiso);
    
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
# sub to setup partition 1. This is the ubuntu-mate
# partition. Filesystem must be built.
# ubuntu-mate iso must be mounted
# parameters passed:
# codename, ubuntuiso-name, chroot-directory, debhome dev label, svn full path, packages list, part_no)
####################################################
sub setpartition {
	my ($ubuntuiso, $upgrade, $debhomedev, $svn, $packages, $part_no)  = @_;

	# debhomemountstatus for debhome mount status, ro, rw or not mounted
	my $debhomemountstatus;
	
	# set up chroot dirs for partition 1 and 2
	my $chroot_dir1 = "/tmp/chroot1";
	my $chroot_dir2 = "/tmp/chroot2";
	
	# hash part parameters: containing parameters that are partition dependent
	my %pparam = ("1" => {"chroot"   => "$chroot_dir1",
		                  "casper"   => "$chroot_dir1/boot/casper",
	                      "label"    => "MACRIUM"},
	              "2" => {"chroot"   => "$chroot_dir2",
					      "casper"   => "$chroot_dir2/boot/casper1",
				          "label"    => "UBUNTU"});

	# some short cuts depending on the parition number
	my $chroot_dir = $pparam{$part_no}->{"chroot"};
	my $casper = $pparam{$part_no}->{"casper"};
	my $label = $pparam{$part_no}->{"label"};
	
	# check MACRIUM and debhomedev is attached
	my $rc = system("blkid -L $debhomedev > /dev/null");
	my $rc1 = system("blkid -L " . $label . " > /dev/null");
	die "Either $label and/or $debhomedev is not attached\n" unless ($rc == 0 and $rc1 == 0);

	# determine if debhomedev is mounted ro, rw or not mounted
	$rc = system("grep -q $debhomedev /etc/mtab");
	if ($rc == 0) {
		# debhomedev is mounted.
		# determine if it is ro or rw
		if (system("grep $debhomedev.*ro /etc/mtab") == 0) {
			# debhome dev mounted ro
			$debhomemountstatus = "ro";
			print "$debhomedev is mounted ro\n";
		} elsif ( system("grep $debhomedev.*rw /etc/mtab") == 0) {
			# debhome dev mount rw
			$debhomemountstatus = "rw";
			print "$debhomedev is mounted rw\n";
		} else {
			# debhome dev mount not rw or ro
			die "Error: $debhomedev is mounted but not rw or ro\n";
		}
	} else {
		# debhomedev is not mounted
		$debhomemountstatus = "not mounted";
	}
	
	# get partition_path of partition ex: /dev/sda1
	my $partition_path = `blkid -L $label`;
	chomp $partition_path;
	print $label . " is: $partition_path\n";
	
	# check if the partition, MACRIUM or UBUNTU is mounted at any location
	# un mount it if it is mounted
	my $devandmtpt = `grep "$partition_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($devandmtpt);
	my ($dev, $mtpt) = split /\s+/, $devandmtpt;

	# if label is mounted, un mount it
	if (defined $mtpt) {
		print "$label mounted at: $mtpt\n";
		$rc = system("umount $mtpt");
		die "$label cannot be unmounted\n" unless $rc == 0;
	}

	# unbind chroot and delete chroot dir
	# before deleting chroot mv it to chroot2
	# incase /proc is still bound
	if (-d $chroot_dir){
		# unbind
		unbindall $chroot_dir;
		# move it to /tmp/junk
		system("mv -f $chroot_dir  /tmp/junk");
		
		# remove directory
		$rc = system("rm -rf /tmp/junk");
		die "cannot remove $chroot_dir\n" unless $rc == 0;
		print "removed /tmp/junk\n";
	}
	
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

	$rc = system("mount -o ro,loop " . $ubuntuiso . " /mnt/cdrom");
	die "Could not mount $ubuntuiso\n" unless $rc == 0;

	# get codename
	my $codename = getcodename();
	die "Could not find codename\n" unless $codename;
	print "code name is: $codename\n";

	#####################################################################################
	# copy and edit files to chroot
	#####################################################################################
	# unsquash filesystem.squashfs to the chroot directory
	# the chroot_dir directory must not exist
	$rc = system("unsquashfs -d " . $chroot_dir . " /mnt/cdrom/casper/filesystem.squashfs");
	die "Error unsquashing /mnt/cdrom/casper/filesystem.squashfs\n"unless $rc == 0;
	print "unsquashed filesystem.squashfs\n";
		
	# edit fstab in chroot for debhome which includes debhome
	chdir $chroot_dir . "/etc";
	system("sed -i -e '/LABEL=$debhomedev/d' fstab");
	system("sed -i -e 'a \ LABEL=$debhomedev /mnt/$debhomedev ext4 defaults,noauto 0 0' fstab");

	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	system("cp /etc/network/interfaces " . $chroot_dir . "/etc/network/");

	# generate chroot_dir/etc/apt/sources.list
	# and chroot_dir/etc/sources.list.d/debhome.list
	setaptsources ($codename, $chroot_dir);
	system("cp -dR /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d " . $chroot_dir . "/etc/apt/");

	# testing for convenience
	# system("cp -v /home/robert/my-linux/livescripts/* $chroot_dir/usr/local/bin/");

	# export livescripts from subversion
	$rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts " . $chroot_dir . "/usr/local/bin/");
	die "Could not export liveinstall.sh from svn\n" unless $rc == 0;

	# copy svn link to the chroot environment if it exists
	$rc = system("cp -dv /mnt/svn $chroot_dir/mnt/");
	die "Cound not copy link /mnt/svn to $chroot_dir/mnt/svn\n" unless $rc == 0;
	# testing
	
	#############################################################################################
	# enter the chroot environment
	#############################################################################################

	# install apps in the chroot environment
	bindall $chroot_dir;
	
	# parameters must be quoted for Bash
	# liveinstall.sh "debhomedev" "upgrade/noupgrade" "package list"
	$upgrade = "\"" . $upgrade . "\"";
	$packages = "\"" . $packages . "\"";
	my $debhomedevice = "\"" . $debhomedev . "\"";
	$debhomemountstatus = "\"" . $debhomemountstatus . "\"";
	# execute liveinstall.sh in the chroot environment
	$rc = system("chroot $chroot_dir /usr/local/bin/liveinstall.sh $debhomedevice $debhomemountstatus $upgrade $packages");

	# for exiting the chroot environment
	unbindall $chroot_dir;

	# check if liveinstall exited with error in chroot environment
	die "liveinstall.sh exited with error" unless $rc == 0;

	#############################################################################################
	# copy and edit files to chroot/boot
	#############################################################################################
	# mount the partition under chroot/boot, it was unmounted before chroot
	$rc = system("mount -L " . $label . " " . $chroot_dir . "/boot");
	die "Could not mount $label at $chroot_dir/boot\n" unless $rc == 0;
	
	# make casper dir if it does not exist
	if ( -d $casper) {
		# clean directory
		system("rm -rf $casper");
	}
	# create directory
	mkdir $casper;
	
	# if live system was not upgraded copy vmlinuz and initrd from cdrom image
	if ($upgrade ne "\"upgrade\"") {
		# no upgrade, copy vmlinuz and initrd from cdrom image
		system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd " . $casper);
	} else {
		# an upgrade was done. vmlinuz and intird must be copied
		# from the the chroot1/oldboot directory to casper
		$rc = system("cp -v $chroot_dir/oldboot/initrd $casper");
		die "Could not copy initrd\n" unless $rc == 0;
		$rc = system("cp -v $chroot_dir/oldboot/vmlinuz $casper");
		die "Could not copy vmlinuz\n" unless $rc == 0;
		# delete chroot1/oldboot directory
		system("rm -rf $chroot_dir/oldboot");
	}

	# delete ubuntu install files in chroot/boot
	chdir $chroot_dir . "/boot";
	system("rm -rf dists install pool preseed grub");
	
	# copy pool and install files for ubuntu mate
	chdir "/mnt/cdrom";
	system("cp -dR dists install pool preseed " . $chroot_dir . "/boot/");
	
	# setup and install grub if this is the first partition
	grubsetup($ubuntuiso, $chroot_dir, $partition_path, $svn) if $part_no == 1;
	
	# set grub colours
	setgrub($chroot_dir);
	
	# make the persistence file
	chdir $casper;
	system("dd if=/dev/zero of=writable bs=1M count=3000");
	system("mkfs.ext4 -v -j -F writable");
	
	# write new filesystem.squashfs to boot directory
	$rc = system("mksquashfs " . $chroot_dir . " /mnt/tmp/filesystem.squashfs -e boot");
	die "mksquashfs returned and error\n" unless $rc == 0;
	
	$rc = system("mv -vf /tmp/filesystem.squashfs " . $casper);
	die "Could not move /tmp/filesystem.squashfs to $casper\n" unless $rc == 0;
	
	# umount chroot boot
	system("umount " . $chroot_dir . "/boot");
	$rc = system("findmnt " . $chroot_dir . "/boot");
	print "count not umount " . $chroot_dir . "/boot\n" if $rc == 0;

	# un mount /mnt/cdrom
	system("umount -d -v -f /mnt/cdrom");
}

sub usage {
	my ($debhomedev, $svn) = @_;
	print "-1 full name of ubuntu-mate iso for partition 1\n";
	print "-2 full name of ubuntu iso for partition 2\n";
	print "-u do a full-upgrade\n";
	print "-p list of packages to install in chroot in quotes\n";
	print "-l disk label for debhome, default is $debhomedev\n";
	print "-s full path to subversion, default is $svn\n";
	exit 0;
}
##################
# Main entry point
##################

# command line parameters
# -1 ubuntu-mate iso name
# -2 ubuntu iso name
# -p "package list of extra packages
# -u upgrade or not
# -l disk label of debhome
# -s full path to subersion
#
# One or both iso's can be given.
# package list in quotes, if given

# default for local repository debhome
my $debhomedev = "ad64";
# /mnt/svn is a link to subversion
# it must be available for this script
my $svn = "/mnt/svn";

# get command line argument
# this is the name of the ubuntu iso ima
our($opt_u, $opt_1, $opt_2, $opt_p, $opt_l, $opt_s, $opt_h);

# get command line options
getopts('1:2:p:hul:s:d:');


# setup debhome if it has changed from the default
$debhomedev = $opt_l if $opt_l;

# setup subversion if it has changed
$svn = $opt_s if $opt_s;

usage($debhomedev, $svn) if $opt_h;

# check for existence of svn
die "Could not find subversion respository at $svn\n" unless -d $svn;

# packages may or may not have a value
my $packages;

if ($opt_p) {
	# make a list between quotes
	$packages = $opt_p;
} else {
	$packages = "";
}

# if and upgrade is selected
# the modules version matching vmlinuz must be installed
# in the chroot environment	
my $host_version;
my $upgrade;

if ($opt_u) {
	# set the upgrade flag
	$upgrade = "upgrade";
} else {
	# no upgrade
	$upgrade = "";
}

# check if iso 1 exists
if ($opt_1){
	die "$opt_1 does not exist\n" unless -f $opt_1;
}

# check if iso 2 exists
if ($opt_2) {
	die "$opt_2 does not exist\n" unless -f $opt_2
}
# invoke set partition for each iso given
if ($opt_1) {
	setpartition($opt_1, $upgrade, $debhomedev, $svn, $packages, 1);
}

# invoke set partition for each iso given
if ($opt_2) {
	setpartition($opt_2, $upgrade, $debhomedev, $svn, $packages, 2);
}
