#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;

#######################################################
# this script makes a live system on MACRIUM and UBUNTU paritions
# although UBUNTU is not often used
# Macrium Reflect 7 must have been installed into partition 1.
#
#
# command line parameters:
# makelive.pl -1 ubuntu-mate iso name | -2 ubuntu iso name and -u for upgrade and -p package list
#
# the disk
# partition 1 8G    [MACRIUM] fat32   contains macrium and ubuntu-mate, boots from grub uuid = AED6-434E
# partition 2 2G    [RECOVERALL]  fat32   contains windows recovery for lenovo and desktop
# partition 3 rest  [ele]     ntfs    contains backup files and sources for windows recovery, Lenovo and desktop
#
#######################################################

# this sub operates on the list @ARGV
# all the switches in the ARGV list are checked to see if they have arguments
# if they do not have arguments, the default arguments are inserted into ARGV
# so that getopts will not fail.
# no parameters are passed and none are returned.

sub defaultparameter {

	# hash supplying default arguments to switches
	# -b is for mounting bit locker drives
	# -v is for mounting vera containers
	# -u is for unmounting any drive
	# the default argument, if not given on the command line is all drives
	my %defparam = ( -1 => "none",
			 -2 => "none");

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
# sub to make filesystem.squashfs.
# dochroot must have been done
# filesystem.squashfs is written to chroot1/dochroot
# parameters: chroot directory
sub makefs {
	my $chroot_dir = $_[0];
	
	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";

	# if the file exists, delete it
	# or mksquashfs will fail.
	unlink "$chroot_dir/dochroot/filesystem.squashfs";
	
	# make the file system the boot directory must be included, config-xxxx file is needed by initramfs during install
	my $rc = system("mksquashfs " . $chroot_dir . " $chroot_dir/dochroot/filesystem.squashfs -e oldboot -e dochroot -e upgrade -e packages");
	die "mksquashfs returned and error\n" unless $rc == 0;
}

# sub to edit grub default and set the theme in the filesystem.squashfs
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
	
############################################################
# sub to mount cdrom
# un mounts anything on /mnt/cdrom
# then mounts cdrom at /mnt/cdrom
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

####################################################################
# sub to set up new chroot environment.
# the environment is copied from the cdrom
# requires svn and mountcdrom to be mounted
# parameters passed: chroot_directory, debhomedevice, svn path
####################################################################
sub createchroot {
	# creating new chroot environment
	my ($chroot_dir, $debhomedev, $svn) = @_;
	my $rc;
		
	# delete the old chroot environment if it exists
	if (-d $chroot_dir) {
		unbindall $chroot_dir;
		# check if $chroot_dir/boot is mounted
		# need to protect the live drive
		# incase the binds are still active
		$rc = system("findmnt $chroot_dir/boot");
		if ($rc == 0) {
			# un mount drive
			$rc = system("umount -v -f $chroot_dir/boot");
			die "Could not umount $chroot_dir/boot\n" unless $rc == 0;
		}

		# check if debhomedev is mounted
		$rc = system("findmnt $chroot_dir/mnt/$debhomedev");
		if ($rc == 0) {
			# un mount debhomedev
			$rc = system("umount -v -f $chroot_dir/mnt/$debhomedev");
			die "Could not umount $chroot_dir/mnt/$debhomedev" unless $rc == 0;
		}

		# move it to /tmp/junk
		$rc = system("mv -f $chroot_dir  /tmp/junk");
		die "Could not move $chroot_dir to /tmp/junk" unless $rc == 0;
		
		# remove directory
		$rc = system("rm -rf /tmp/junk");
		die "cannot remove $chroot_dir\n" unless $rc == 0;
		print "removed /tmp/junk\n";
	}

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
		
	# edit fstab in chroot so debhome can be mounted
	chdir $chroot_dir . "/etc";
	system("sed -i -e '/LABEL=$debhomedev/d' fstab");
	system("sed -i -e 'a \ LABEL=$debhomedev /mnt/$debhomedev ext4 defaults,noauto 0 0' fstab");

	# make directory for debhomedev to be mounted in the chroot environment
	mkdir "$chroot_dir/mnt/$debhomedev" unless -d "$chroot_dir/mnt/$debhomedev";

	# make the link for /mnt/debhome -> /chroot_dir/mnt/$debhomedev in the chroot environment
	$rc = symlink "$chroot_dir/mnt/$debhomedev", "$chroot_dir/mnt/debhome";
	die "Error making debhome link: $!" unless $rc == 1;
	
	# copy resolv.conf and interfaces so network will work
	system("cp /etc/resolv.conf /etc/hosts " . $chroot_dir . "/etc/");
	system("cp /etc/network/interfaces " . $chroot_dir . "/etc/network/");

	# generate chroot_dir/etc/apt/sources.list
	# and chroot_dir/etc/sources.list.d/debhome.list
	setaptsources ($codename, $chroot_dir, $svn);
	system("cp -dR /etc/apt/trusted.gpg.d " . $chroot_dir . "/etc/apt/");
	system("cp -a /etc/apt/trusted.gpg " . $chroot_dir . "/etc/apt/") if -f "/etc/apt/trusted.gpg";

	# testing for convenience
	# system("cp -v /home/robert/my-linux/livescripts/* $chroot_dir/usr/local/bin/");

	# liveinstall is now installed from a package
	# export livescripts from subversion
	# $rc = system("svn export --force --depth files file://$svn/root/my-linux/livescripts " . $chroot_dir . "/usr/local/bin/");
	# die "Could not export liveinstall.sh from svn\n" unless $rc == 0;

	# copy svn link to the chroot environment if it exists
	$rc = system("cp -dv /mnt/svn $chroot_dir/mnt/");
	die "Could not copy link /mnt/svn to $chroot_dir/mnt/svn\n" unless $rc == 0;

	# copy xwindows themes and icons to /usr/share
	# if themes.tar.xz and icons.tar.xz are found
	if (-f "/mnt/$debhomedev/debhome/xconfig/themes.tar.xz") {
		$rc = system("tar --xz -xf /mnt/$debhomedev/debhome/xconfig/themes.tar.xz -C $chroot_dir/usr/share");
		die "Could not extract themes from /mnt$debhomedev/debhome/xconfig/themes.tar.xz" unless $rc == 0;
	}

	# if themes.tar.xz and icons.tar.xz are found
	if (-f "/mnt/$debhomedev/debhome/xconfig/icons.tar.xz") {
		$rc = system("tar --xz -xf /mnt/$debhomedev/debhome/xconfig/icons.tar.xz -C $chroot_dir/usr/share");
		die "Could not extract themes from /mnt$debhomedev/debhome/xconfig/icons.tar.xz" unless $rc == 0;
	}
	
	
}

###############################################
# sub to change root  and run liveinstall.sh
# makes a dir dochroot to indicate dochroot was run
# also deletes filesystem.squashfs in docchroot
# since it will now change.
# installfs will use filesystem.squashfs if it exists
# requires debhomedev to be mounted
# also requires svn if packages and or upgrade are done.
# parameters: chroot_directory, debhome_device, upgrade, packages_list
###############################################
sub dochroot {
	my ($chroot_dir, $debhomedev, $upgrade, $packages) = @_;

	# debhomemountstatus for debhome mount status, ro, rw or not mounted
	my ($rc, $debhomemountstatus);
	
	# determine if debhomedev is mounted ro, rw or not mounted
	$rc = system("grep -q $debhomedev /etc/mtab");
	if ($rc == 0) {
		# debhomedev is mounted.
		# determine if it is ro or rw
		if (system("grep $debhomedev.*ro /etc/mtab") == 0) {
			# debhome dev mounted ro
			$debhomemountstatus = "\"ro\"";
			print "$debhomedev is mounted ro\n";
		} elsif ( system("grep $debhomedev.*rw /etc/mtab") == 0) {
			# debhome dev mount rw
			$debhomemountstatus = "\"rw\"";
			print "$debhomedev is mounted rw\n";
		} else {
			# debhome dev mount not rw or ro
			die "Error: $debhomedev is mounted but not rw or ro\n";
		}
	} else {
		# debhomedev is not mounted
		$debhomemountstatus = "\"not mounted\"";
	}
	#############################################################################################
	# enter the chroot environment
	#############################################################################################

	# install apps in the chroot environment
	bindall $chroot_dir;
	
	# parameters must be quoted for Bash
	# liveinstall.sh "debhomedev" "debhomemountstatus" "upgrade/noupgrade" "package list"
	# make parameters list for liveinstall.sh
	my $parameters = "";
	$parameters = " -u" if $upgrade;
	$parameters = "-p " . $packages  . $parameters if $packages;
	
	$parameters = "-d $debhomedev -s $debhomemountstatus " . $parameters;
	
	# execute liveinstall.sh in the chroot environment
	print "parameters: $parameters\n";

	#################=============================#######################
	# to be done.
	# liveinstall is now a package and must be installed first
	# in chroot environment
	# apt update
	# apt install -y liveinstall
	# liveinstall depends on
	#	subversion
	#	git
	#	editfstab
	#	initialise-linux
	#####################################################################
	$rc = system("chroot $chroot_dir /usr/local/bin/liveinstall.sh $parameters");

	# for exiting the chroot environment
	unbindall $chroot_dir;

	# check if liveinstall exited with error in chroot environment
	die "liveinstall.sh exited with error" unless $rc == 0;
	# liveinstall.sh will create directory dochroot
	# to indicate chroot was done.
	# filesystem.squashfs must be deleted in /dochroot
	# because the filesystem will have changed.
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
	my ($codename, $chroot_dir, $svn) = @_;
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
	# $rc = system("svn export --force file://$svn/root/my-linux/sources/amd64/debhome.sources  " . $chroot_dir . "/etc/apt/sources.list.d/");
	# die "Could not export debhome.sources from svn\n" unless $rc == 0;

	# get the public key for debhome
	# make the /etc/apt/keyrings directory if it does not exist
	#mkdir "/etc/apt/keyrings" unless -d "/etc/apt/keyrings";
	
	# $rc = system("svn export --force file://$svn/root/my-linux/sources/gpg/debhomepubkey.asc  " . $chroot_dir . "/etc/apt/keyrings/");
	#die "Could not export debhome.sources from svn\n" unless $rc == 0;

}

# this sub sets up grub and installs it.
# this is only necessary for partition 1
# the call: installgrub(ubuntu_iso_name, chroot_directory, partition_path, subversion path)
#################################################
sub installgrub {
	
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
# sub to build filesystem.squashfs, copy dists, install
# pool preseed to /boot on drive.
# install and edit grub
# create the writable file for persistence
# and copy to casper
# uses filesystem.squashfs if it exists in dochroot
# else it builds if from scratch.
# this speeds up the process of install if filesystem.squashfs has not changed
# requires MACRIUM/UBUNTU , cdrom and svn to be mounted
####################################################
sub installfs {
	# parameters
	my ($label, $ubuntuiso, $casper, $svn, $chroot_dir, $part_no) = @_;
	
	# check if chroot environment exists
	die "$chroot_dir does not exist\n" unless -d $chroot_dir;

	# check that dochroot has been executed previously
	die "dochroot has not been executed\n" unless -d "$chroot_dir/dochroot";
	
	# check MACRIUM/UBUNTU is attached
	my $rc = system("blkid -L " . $label . " > /dev/null");
	die "$label is not attached\n" unless $rc == 0;
	
	# get partition_path of partition MACRIUM/UBUNTU ex: /dev/sda1
	my $partition_path = `blkid -L $label`;
	chomp $partition_path;
	print $label . " is: $partition_path\n";
	
	# check if the partition, MACRIUM or UBUNTU is mounted at any location
	# un mount it if it is mounted
	my $devandmtpt = `grep "$partition_path" /etc/mtab | cut -d " " -f 1-2`;
	chomp($devandmtpt);
	my ($dev, $mtpt) = split /\s+/, $devandmtpt;

	# if label MACRIUM|UBUNTU is mounted, un mount it
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

	# mount the partition MACRIUM/UBUNTU under 
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
	
	# check if the kernel in chroot was upgraded by liveinstall.sh by checking existence of /chroot1/oldboot
	# if not upgraded use vmlinuz, initrd from cdrom
	# else use vmlinuz, initrd from /chroot1/oldboot.
	if (! -d "$chroot_dir/oldboot") {
		# no upgrade, copy vmlinuz and initrd from cdrom image
		system("cp -vf /mnt/cdrom/casper/vmlinuz /mnt/cdrom/casper/initrd " . $casper);
	} else {
		# an upgrade was done. vmlinuz and intird must be copied
		# from the the chroot1/oldboot directory to casper
		$rc = system("cp -v $chroot_dir/oldboot/initrd $casper");
		die "Could not copy initrd\n" unless $rc == 0;
		$rc = system("cp -v $chroot_dir/oldboot/vmlinuz $casper");
		die "Could not copy vmlinuz\n" unless $rc == 0;
		# do not delete oldboot, incase chroot1 is used again
	}

	# delete ubuntu install files in chroot/boot
	chdir $chroot_dir . "/boot";
	system("rm -rf dists install pool preseed grub");
	
	# copy pool and install files for ubuntu mate
	chdir "/mnt/cdrom";
	system("cp -dR dists install pool preseed " . $chroot_dir . "/boot/");
	
	# setup and install grub if this is the first partition
	installgrub($ubuntuiso, $chroot_dir, $partition_path, $svn) if $part_no == 1;
	
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
# sub to initialise the setup of partition 1|2. This is the ubuntu-mate
# or ubuntu partition.
# if -c given create new chroot from scratch or use existing one
# parameters passed:
# createchroot, ubuntuiso-name, upgrade, debhome dev label, svn full path, packages list, part_no)
####################################################
sub initialise {
	my ($chroot, $chrootuse, $doinstall, $makefs, $ubuntuiso, $upgrade, $debhomedev, $svn, $packages, $part_no)  = @_;

	# set up chroot dirs for partition 1 and 2
	my $chroot_dir1 = "/chroot1";
	my $chroot_dir2 = "/chroot2";
	
	# hash part parameters: containing parameters that are partition dependent
	my %pparam = ("1" 		=> {"chroot"	=> "$chroot_dir1",
					    "casper"	=> "$chroot_dir1/boot/casper",
					    "label"	=> "MACRIUM"},
	              "2" 		=> {"chroot"  	=> "$chroot_dir2",
					      "casper"  => "$chroot_dir2/boot/casper1",
				          "label"    	=> "UBUNTU"});

	# some short cuts depending on the parition number
	my $chroot_dir = $pparam{$part_no}->{"chroot"};
	my $casper = $pparam{$part_no}->{"casper"};
	my $label = $pparam{$part_no}->{"label"};
	
	# if p or u given then set chrootuse
	# if chroot does not exist then set chroot
	print "packages: $packages\n" if $packages;
	print "upgrade: $upgrade\n" if $upgrade;
	
	# if packages or upgrade defined, chrootuse must be set
	if ($packages or $upgrade) {
		# dochroot must be done
		$chrootuse = "use";
		$chroot = "new" unless -d $chroot_dir;
	}
	print "chroot: $chroot\n" if $chroot;
	print "chrootuse: $chrootuse\n" if $chrootuse;
	 
	# if not creating chroot env, check the old one exists
	if ($chrootuse and ! $chroot) {
		die "chroot environment $chroot_dir does not exist\n" unless -d $chroot_dir;
	}

	# check debhomedev is attached
	# only install does not need debhomedev mounted
	# it must be attached $chroot defined, upgrade or packages to install
	if ($upgrade or $packages or $chrootuse) {
		my $rc = system("blkid -L $debhomedev > /dev/null");
		die "$debhomedev is not attached\n" unless $rc == 0;
	}
	
	# mount the cdrom for create chroot or install
	if ($chroot or $doinstall) {
		# check ubuntuiso
		if ($ubuntuiso ne "none") {
			mountcdrom $ubuntuiso;
		} else {
			print "cdrom image $ubuntuiso: cannot be mounted\n";
		}
	}
	
	# if creating new chroot and
#	print "createchroot $chroot_dir $debhomedev $svn\n" if $chroot eq "new";
	createchroot($chroot_dir, $debhomedev, $svn) if $chroot;

	# chroot and run liveinstall.sh
#	print "dochroot $chroot_dir $debhomedev $upgrade $packages\n" if $chrootuse eq "use";
	dochroot($chroot_dir, $debhomedev, $upgrade, $packages) if $chrootuse;
	
	# make filesystem.squashfs if not installing
	makefs($chroot_dir) if $makefs;

	# install in MACRIUM/UBUNTU
#	print "installfs $label $ubuntuiso $casper $svn $upgrade $chroot_dir $part_no\n" if $doinstall;
	installfs($label, $ubuntuiso, $casper, $svn, $chroot_dir, $part_no) if $doinstall;

	# un mount /mnt/cdrom if it is mounted
	my $rc = system("findmnt /mnt/cdrom");
	system("umount -d -v -f /mnt/cdrom") if $rc == 0;
}

sub usage {
	my ($debhomedev, $svn) = @_;
	print "-1 full name of ubuntu-mate iso for partition 1\n";
	print "-2 full name of ubuntu iso for partition 2\n";
	print "-u do a full-upgrade -- needs partition number\n";
	print "-c create changeroot -- needs iso image\n";
	print "-e use existing changeroot -- takes precedence over -c needs -- parition number\n";
	print "-m make filesystem.squashfs, dochroot must be complete -- needs parition number\n";
	print "-p list of packages to install in chroot in quotes -- needs parition number\n";
	print "-l disk label for debhome, default is $debhomedev\n";
	print "-s full path to subversion, default is $svn\n";
	print "-i install the image to MACRIUM/UBUNTU -- needs iso image\n";
	exit 0;
}
##################
# Main entry point
##################

# command line parameters
# -1 ubuntu-mate iso name
# -2 ubuntu iso name
# -c use existing /chroot1 or /chroot2, do not create a new one for partition 1|2
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
our($opt_m, $opt_i, $opt_c, $opt_e, $opt_u, $opt_1, $opt_2, $opt_p, $opt_l, $opt_s, $opt_h);

# if -u or -p is given but not -c then chroot = use should be used.
# get command line options

# if -1 or -2 is given without parameters, then no cdrom should be use
# makefs, dochroot do not need a cdrom image
defaultparameter();

getopts('mice1:2:p:hul:s:d:');

# setup debhome if it has changed from the default
$debhomedev = $opt_l if $opt_l;

# setup subversion if it has changed
$svn = $opt_s if $opt_s;

usage($debhomedev, $svn) if $opt_h;

# if install option was given
# setup doinstall
# if install and makefs are given
# then makefs has no effect
my $makefs;
$makefs = $opt_m if $opt_m;

my $doinstall;
if ($opt_i) {
	$doinstall = $opt_i;
	# makefs has no effect
	undef $makefs;
}

# set changeroot usechageroot
my ($chroot, $chrootuse);
$chroot = "new" if $opt_c;
$chrootuse = "use" if $opt_e;


# check for existence of svn
# svn is not needed for makefs only, but for create chroot, dochroot, installfs
if ($chroot or $chrootuse or $doinstall) {
	die "Could not find subversion respository at $svn\n" unless -d $svn;
}

# check for packages and upgrade
my $packages;
$packages = "\"" . $opt_p . "\"" if $opt_p;

my $upgrade;
$upgrade = "upgrade" if $opt_u;

# check if iso 1 exists
if ($opt_1){
	# if opt_1 is a cdrom image, check it exists
	die "$opt_1 does not exist\n" unless -f $opt_1 or $opt_1 eq "none";

	# if cdrom and image is set to none
	# then chroot and doinstall cannot be invoked
	if (($chroot or $doinstall) and $opt_1 eq "none") {
		die "create chroot and install need a cdrom image\n";
	}
}

# check if iso 2 exists
if ($opt_2) {
	# if opt_2 is a cdrom image, check it exists
	die "$opt_2 does not exist\n" unless -f $opt_2 or $opt_2 eq "none";

	# if cdrom and image is set to none
	# then chroot and doinstall cannot be invoked
	if (($chroot or $doinstall) and $opt_2 eq "none") {
		die "create chroot and install need a cdrom image\n";
	}
}


# invoke set partition for each iso given
if ($opt_1) {
	initialise($chroot, $chrootuse, $doinstall, $makefs, $opt_1, $upgrade, $debhomedev, $svn, $packages, 1);
}

# invoke set partition for each iso given
if ($opt_2) {
	initialise($chroot, $chrootuse, $doinstall, $makefs, $opt_2, $upgrade, $debhomedev, $svn, $packages, 2);
}
