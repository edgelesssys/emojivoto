# using a top level cmake with add_subdirectory(..) introduces issues with the config tool regarding path, for now use this script to build them
ROOT_DIR=$(pwd)
echo "build emoji-svc"
mkdir -p $ROOT_DIR/emojivoto-emoji-svc/build && cd $ROOT_DIR/emojivoto-emoji-svc/build && cmake .. && make
echo "build voting-svc"
mkdir -p $ROOT_DIR/emojivoto-voting-svc/build && cd $ROOT_DIR/emojivoto-voting-svc/build && cmake .. && make
echo "build web"
mkdir -p $ROOT_DIR/emojivoto-web/build && cd $ROOT_DIR/emojivoto-web/build && cmake .. && make
