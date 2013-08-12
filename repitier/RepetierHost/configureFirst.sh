#!/bin/bash
echo "Installing slic3r source version"
DIR=`pwd`
echo "#!/bin/sh" > repetierHost
echo "cd ${DIR}" >> repetierHost
echo "mono RepetierHost.exe -home ${DIR}&" >> repetierHost
sudo chmod 755 repetierHost
sudo chmod a+rx ../RepetierHost
sudo chmod -R a+r *
sudo chmod -R a+x data
sudo chmod -R a+rwx Slic3r
sudo chmod a+x installDep*
sudo rm /usr/bin/repetierHost
sudo ln -s ${DIR}/repetierHost /usr/bin/repetierHost

echo "Configuration finished."
echo "Make sure, your user has permission to connect to the serial port."
echo "For debian and clones use:"
echo "usermod -a -G dialout yourUserName"
echo "IMPORTANT: The host works natively with the source version for linux."
echo "Check https://github.com/alexrj/Slic3r/wiki/Running-Slic3r-from-git-on-GNU-Linux"
echo "on how to resolve all dependencies. You can omit the 'Get slic3r' section."
echo ""
if [ -f /usr/bin/yum ]
then
  echo "Fedora like yum installer detected." 
  while true; do
    read -p "Shall I try to install required modules [y/n]?" yn
    case $yn in
        [Yy]* ) sudo ./installDependenciesFedora; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
  done    
fi
if [ -f /usr/bin/apt-get ]
then
echo "Debian/Ubuntu like linux detected. You can try to"
echo "install needed software automatically. You can do this any time later"
echo "by running installDependenciesDebian."
  while true; do
    read -p "Shall I try to install required modules [y/n]?" yn
    case $yn in
        [Yy]* ) sudo ./installDependenciesDebian; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
  done    
fi

