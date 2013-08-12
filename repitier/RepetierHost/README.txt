Installation instructions

1. Open a terminal
2. Go to the directory, where you want to have the installation
3. tar -xzf repetierHostLinux.tgz
   change tar file accordingly.
4. cd RepetierHost
5. sh configureFirst.sh
6. Make sure your user has permission to use the serial port. On
   Debian this requires membership in group dialout. To add a user
   into this group enter:
      usermod -a -G dialout yourUserName
7. You will be questioned to install dependencies. Answer yes if you are using
   a Debian like distribution (Ubuntu, Mint, ...). This will most probably di
   all work needed, to get it running.
   
After that, you have a link in /usr/bin so you can start the host from
everywhere with

repetierHost

Known issues:
- You may see an OpenGL warning at startup. Ignore it.
- Sometimes the start fails. Just start again.


First steps:
Create a workdir under Config->Repetier settings
Configure printer
Configure your slicer. Slic3r should work out of the box. Just adjust the
slicing parameter to you likes.
If you want to use Skeinforge, install it and configure the path to Skeinforge.


