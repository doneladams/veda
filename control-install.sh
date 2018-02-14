#!/bin/bash
# устанавливает среду для последующей компиляции, берет новые исходники зависимостей из github, но не собирает

DMD_VER=2.073.2
DUB_VER=1.2.0
GO_VER=go1.9.3
TARANTOOL_VER=1.7.6
MSGPUCK_VER=2.0

# Get other dependencies
LIB_NAME[1]="libevent-pthreads-2.0-5"
LIB_NAME[3]="libevent-dev"
LIB_NAME[4]="libssl-dev"
LIB_NAME[5]="libmysqlclient-dev"
LIB_NAME[6]="cmake"
LIB_NAME[7]="libtool"
LIB_NAME[8]="pkg-config"
LIB_NAME[9]="build-essential"
LIB_NAME[10]="autoconf"
LIB_NAME[11]="automake"

LIB_OK="Status: install ok installed"
F_UL=0

#echo "--- INSTALL VIBE.D ---"
#mkdir tmp
#cd tmp
#wget https://github.com/vibe-d/vibe.d/archive/v0.7.30.tar.gz
#tar -xvzf v0.7.30.tar.gz
#mkdir ~/.dub/packages/vibe-d-0.7.30
#mkdir ~/.dub/packages/vibe-d-0.7.30/vibe-d
#cp -r ./vibe.d-0.7.30/* ~/.dub/packages/vibe-d-0.7.30/vibe-d
#cp ./../source/vibe-d/dub.json ~/.dub/packages/vibe-d-0.7.30/vibe-d
#rm ~/.dub/packages/vibe-d-0.7.30/vibe-d/dub.sdl
#cd ..

### RUST LANG ###

if ! rustc -V; then
    echo "--- INSTALL RUST ---"
    curl https://sh.rustup.rs -sSf | sh -s -- -y
else
    echo "--- UPDATE RUST ---"
    rustup update stable
fi


rustc -V
cargo -V

### D LANG ###

# Get right version of DMD
if ! dmd --version | grep $DMD_VER ; then    
    echo "--- INSTALL DMD ---"
    wget http://downloads.dlang.org/releases/2.x/$DMD_VER/dmd_$DMD_VER-0_amd64.deb
    sudo dpkg -i dmd_$DMD_VER-0_amd64.deb
    rm dmd_$DMD_VER-0_amd64.deb
    rm -r ~/.dub
fi

# Get right version of DUB
if ! dub --version | grep $DUB_VER ; then
    echo "--- INSTALL DUB ---"
    wget http://code.dlang.org/files/dub-$DUB_VER-linux-x86_64.tar.gz
    tar -xvzf dub-$DUB_VER-linux-x86_64.tar.gz    
    sudo cp ./dub /usr/bin/dub
    rm dub-$DUB_VER-linux-x86_64.tar.gz
    rm dub
fi

### GO LANG ###

    echo "--- INSTALL GOLANG ---"
    mkdir tmp
    cd tmp
    wget https://storage.googleapis.com/golang/$GO_VER.linux-amd64.tar.gz
    tar -xf $GO_VER.linux-amd64.tar.gz

    if env | grep -q ^GOROOT=
    then
        sudo rm -rf $GOROOT
    else
        export GOROOT=/usr/local/go
        export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"
        echo 'export GOROOT=/usr/local/go'  >> $HOME/.profile
        echo 'export PATH=$PATH:$GOROOT/bin:$GOPATH/bin'  >> $HOME/.profile
    fi

    export GOPATH=$HOME/go
    echo 'export GOPATH=$HOME/go'  >> $HOME/.bashrc
    source ~/.bashrc

    sudo rm -rf /usr/local/go
    sudo rm -rf /usr/bin/go
    sudo rm -rf /usr/bin/gofmt
    sudo mv go $GOROOT

    go version
    cd ..

go get github.com/gorilla/websocket
go get github.com/divan/expvarmon
go get -v gopkg.in/vmihailenco/msgpack.v2
cp -a ./source/golang-third-party/cbor $GOPATH/src
ls $HOME/go 

### LIBS FROM APT ###

for i in "${LIB_NAME[@]}"; do

    L1=`dpkg -s $i | grep 'install ok'`

    if  [ "$L1" != "$LIB_OK" ]; then

	if [ $F_UL == 0 ]; then
	    sudo apt-get update
	    F_UL=1
	fi 

        sudo apt-get install -y $i
    fi

done


### TARANTOOL SERVER ###

if ! tarantool -V | grep $TARANTOOL_VER; then

curl http://download.tarantool.org/tarantool/1.7/gpgkey | sudo apt-key add -
release=`lsb_release -c -s`

# install https download transport for APT
sudo apt-get -y install apt-transport-https

# append two lines to a list of source repositories
sudo rm -f /etc/apt/sources.list.d/*tarantool*.list
sudo tee /etc/apt/sources.list.d/tarantool_1_7.list <<- EOF
deb http://download.tarantool.org/tarantool/1.7/ubuntu/ $release main
deb-src http://download.tarantool.org/tarantool/1.7/ubuntu/ $release main
EOF
    
# install
sudo apt-get update
sudo apt-get -y install tarantool
sudo apt-get -y install tarantool-dev

tarantool -V

fi

### LIB WEBSOCKETS ###

if ! ldconfig -p | grep libwebsockets; then

    # make libwebsockets dependency
    mkdir tmp
    wget https://github.com/warmcat/libwebsockets/archive/v2.0.3.tar.gz -P tmp
    cd tmp
    tar -xvzf v2.0.3.tar.gz
    cd libwebsockets-2.0.3
    mkdir build
    cd build
    cmake ..
    make
    sudo make install
    sudo ldconfig
    cd ..
    cd ..
    cd ..

fi

### LIB NANOMSG ###

if ! ldconfig -p | grep libnanomsg; then

    # make nanomsg dependency
    mkdir tmp
    wget https://github.com/nanomsg/nanomsg/archive/1.1.2.tar.gz -P tmp
    cd tmp
    tar -xvzf 1.1.2.tar.gz
    cd nanomsg-1.1.2
    mkdir build
    cd build
    cmake ..
    make
    sudo make install

    echo '/usr/local/lib/x86_64-linux-gnu' > x86_64-linux-gnu-local.conf
    sudo cp x86_64-linux-gnu-local.conf /etc/ld.so.conf.d/x86_64-linux-gnu-local.conf
    sudo ldconfig

    cd ..
    cd ..
    cd ..

fi

### LIB TRAILDB ###

if ! ldconfig -p | grep libtraildb; then

    sudo apt-get install -y libarchive-dev pkg-config
    sudo apt-get remove -y libjudydebian1
    sudo apt-get remove -y libjudy-dev

    mkdir tmp
    cd tmp

    wget https://mirrors.kernel.org/ubuntu/pool/universe/j/judy/libjudy-dev_1.0.5-5_amd64.deb \
     https://mirrors.kernel.org/ubuntu/pool/universe/j/judy/libjudydebian1_1.0.5-5_amd64.deb
    sudo dpkg -i libjudy-dev_1.0.5-5_amd64.deb libjudydebian1_1.0.5-5_amd64.deb


    wget https://github.com/traildb/traildb/archive/0.5.tar.gz -P tmp
    cd tmp
    tar -xvzf 0.5.tar.gz

    cd traildb-0.5
    ./waf configure
    ./waf build
    sudo ./waf install
    sudo ldconfig
    cd ..
    cd ..
    cd ..
fi

### LIB RAPTOR ###

sudo apt-get remove -y libraptor2-0
ldconfig -p | grep libraptor2
if ! ldconfig -p | grep libraptor2; then

    sudo apt-get install -y gtk-doc-tools
    sudo apt-get install -y libxml2-dev
    sudo apt-get install -y flex
    sudo apt-get install -y bison

    mkdir tmp
    cd tmp

    wget https://github.com/dajobe/raptor/archive/raptor2_2_0_15.tar.gz -P .
    tar -xvzf raptor2_2_0_15.tar.gz

    cd raptor-raptor2_2_0_15
    autoreconf -i
    ./autogen.sh
    ./make
    sudo make install
    sudo ldconfig
    cd ..
    cd ..
    cd ..

fi

if ! ldconfig -p | grep libtarantool; then

    TTC=213ed9f4ef8cc343ae46744d30ff2a063a8272e5

    mkdir tmp
    cd tmp

    wget https://github.com/tarantool/tarantool-c/archive/$TTC.tar.gz -P .
    tar -xvzf $TTC.tar.gz

    wget https://github.com/tarantool/msgpuck/archive/$MSGPUCK_VER.tar.gz -P third_party/msgpuck -P .
    tar -xvzf $MSGPUCK_VER.tar.gz

    cp msgpuck-$MSGPUCK_VER/* tarantool-c-$TTC/third_party/msgpuck 
    cd tarantool-c-$TTC

    mkdir build
    cd build
    cmake ..
    make
    sudo make install
    sudo ldconfig

    cd ..
    cd ..

fi

if ! ldconfig -p | grep libmdbx; then

    TTC=24a8bdec49ee360bf0412631ff8931de91e109fc

    mkdir tmp
    cd tmp

    wget https://github.com/leo-yuriev/libmdbx/archive/$TTC.tar.gz -P .
    tar -xvzf $TTC.tar.gz

    cd libmdbx-$TTC

    make

    cp src/tools/*.1 ./

    sudo make install
    sudo ldconfig

    cd ..

fi

