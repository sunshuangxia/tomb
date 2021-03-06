#!/usr/bin/env bash
#Copyright (C) dirlt

APP_NAME="%(artifactId)s"
JAR_NAME="%(artifactId)s.jar"

# TODO(dirlt): app version
APP_VERSION="0.0.1"

# TODO(dirlt): main class.
JAR_MAIN="%(groupId)s.%(artifactId)s.%(mainClass)sServer"

# TODO(dirlt): jvm options.
GC_OPTS="-XX:+UseConcMarkSweepGC -XX:+UseParNewGC"
HEAP_OPTS="-Xms8192m -Xmx8192m -XX:NewSize=1024m"
JMX_OPTS="-Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false"

LOG4J_OPTS="-Dlog4j.configuration=file:./config/log4j.properties"
JVM_OPTS="-Dfile.encoding=UTF-8 -server $HEAP_OPTS $GC_OPTS $JMX_OPTS $LOG4J_OPTS "

LOG4J_DEBUG_OPTS="-Dlog4j.configuration=file:./config/log4j.debug.properties"
JVM_DEBUG_OPTS="-Dfile.encoding=UTF-8 -server $HEAP_OPTS $GC_OPTS $JMX_OPTS $LOG4J_DEBUG_OPTS "

# TODO(dirlt): app options.
APP_OPTS="-f config/release.scala"

APP_DEBUG_OPTS="-f config/debug.scala"

# ====================

DIST_NAME="${APP_NAME}-dist-${APP_VERSION}"

PID_FILE="$APP_NAME.pid"

# ====================

running() {
  # File does not exist, we can run
    [ -f $PID_FILE ] || return 1
  # Read PID from file
    read PID < $PID_FILE
  # pid file is empty
    [ ! -z "$PID" ] || return 1
  # File exists but process does not.
    [ -d /proc/${PID} ] || return 1
    return 0
}

find_java() {
    if [ ! -z "$JAVA_HOME" ]; then
	return
    fi
    for dir in /usr /usr/lib/jvm/java-6-sun /opt/jdk /System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home /usr/java/default; do
	if [ -x $dir/bin/java ]; then
	    JAVA_HOME=$dir
	    break
	fi
    done
}


find_target() {
    jar=`ls target/${APP_NAME}-*-jar-with-dependencies.jar 2>/dev/null`
    if [ "x$jar" != "x" ]
    then
	TARGET=$jar
	return
    else
	echo "*** $APP_NAME jar missing"
	exit 1
    fi
}

find_source() {
    jar=`ls target/${APP_NAME}-*-sources.jar 2>/dev/null`
    if [ "x$jar" != "x" ]
    then
	SOURCE=$jar
	return
    else
	echo "*** $APP_NAME source jar missing"
	exit 1
    fi    
}

pre_dist() {
    find_target
    find_source
    rm -rf $DIST_NAME
    mkdir -p $DIST_NAME
}

do_dist() {    
    mkdir -p $DIST_NAME/target
    cp $TARGET $DIST_NAME/target
    cp $SOURCE $DIST_NAME/target
    cd $DIST_NAME && ln -s target/`basename $TARGET` $JAR_NAME && cd ..
    
    rm -rf config/target/
    rm -rf scripts/target/
    cp -r config $DIST_NAME
    cp -r scripts $DIST_NAME

    cp oracle $DIST_NAME
}

post_dist() {
    tar czvf $DIST_NAME.tgz $DIST_NAME
}


find_java

command=$1
shift 1
case $command in
    start)
	echo -n "Starting $APP_NAME... "

	if [ ! -r $JAR_NAME ]; then
	    echo "FAIL"
	    echo "*** $APP_NAME jar missing: $JAR_NAME - not starting"
	    exit 1
	fi
	if [ ! -x $JAVA_HOME/bin/java ]; then
	    echo "FAIL"
	    echo "*** $JAVA_HOME/bin/java doesn't exist -- check JAVA_HOME?"
	    exit 1
	fi
	if running; then
	    exit 0
	    echo "already running."
	fi

	sh -c "echo $$ > $PID_FILE;"
	exec ${JAVA_HOME}/bin/java ${JVM_OPTS} -cp $JAR_NAME ${JAR_MAIN} ${APP_OPTS} $@
	tries=0
	while ! running; do
	    tries=$((tries + 1))
	    if [ $tries -ge 5 ]; then
		echo "FAIL"
		exit 1
	    fi
	    sleep 1
	done
	echo "done."
	;;

    stop)
	echo -n "Stopping $APP_NAME... "
	if ! running; then
	    echo "wasn't running."
	    exit 0
	fi

	tries=0
	while running; do
	    tries=$((tries + 1))
	    if [ $tries -ge 15 ]; then
		echo "FAILED SOFT SHUTDOWN, TRYING HARDER"
		if [ -f $PID_FILE ]; then
		    kill $(cat $PID_FILE)
		else
		    echo "CAN'T FIND PID, TRY KILL MANUALLY"
		    exit 1
		fi
		hardtries=0
		while running; do
		    hardtries=$((hardtries + 1))
		    if [ $hardtries -ge 5 ]; then
			echo "FAILED HARD SHUTDOWN, TRY KILL -9 MANUALLY"
			kill -9 $(cat $PID_FILE)
		    fi
		    sleep 1
		done
	    fi
	    sleep 1
	done
	echo "done."
	;;

    status)
	if running; then
	    echo "$APP_NAME is running."
	else
	    echo "$APP_NAME is NOT running."
	fi
	;;

    restart)
	$0 stop
	sleep 2
	$0 start
	;;

    run)
	find_target
	${JAVA_HOME}/bin/java ${JVM_OPTS} -cp $TARGET ${JAR_MAIN} ${APP_OPTS} $@
	;;

    debug)
	find_target
	${JAVA_HOME}/bin/java ${JVM_DEBUG_OPTS} -cp $TARGET ${JAR_MAIN} ${APP_DEBUG_OPTS} $@
	;;

    dist)
	pre_dist
	do_dist
	post_dist
	;;

    clean)
	rm -rf $DIST_NAME $DIST_NAME.tgz
	;;

    *)
	echo "Usage: ./oracle {start|stop|restart|status|run|debug|dist|clean}"
	exit 1
	;;
esac

exit 0
