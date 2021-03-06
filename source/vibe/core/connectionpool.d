/**
	Generic connection pool for reusing persistent connections across fibers.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.connectionpool;

import vibe.core.log;
import vibe.core.driver;

import core.thread;


/**
	Generic connection pool class.

	The connection pool is creating connections using the supplied factory function as needed
	whenever lockConnection() is called. Connections are associated to the calling fiber, as long
	as any copy of the returned LockedConnection object still exists. Connections that are not
	associated 
*/
class ConnectionPool(Connection : EventedObject)
{
	private {
		Connection delegate() m_connectionFactory;
		Connection[] m_connections;
		Connection[Task] m_locks;
		int[Connection] m_lockCount;
	}

	this(Connection delegate() connection_factory)
	{
		m_connectionFactory = connection_factory;
	}

	LockedConnection!Connection lockConnection()
	{
		auto fthis = Task.getThis();
		auto pconn = fthis in m_locks;
		if( pconn && *pconn ){
			m_lockCount[*pconn]++;
			return LockedConnection!Connection(this, *pconn);
		}

		size_t cidx = size_t.max;
		foreach( i, c; m_connections ){
			auto plc = c in m_lockCount;
			if( !plc || *plc == 0 ){
				cidx = i;
				break;
			}
		}

		Connection conn;
		if( cidx != size_t.max ){
			logDebug("returning %s connection %d of %d", Connection.stringof, cidx, m_connections.length);
			conn = m_connections[cidx];
			if( fthis != Task() ) conn.acquire();
		} else {
			logDebug("creating %s new connection of %d", Connection.stringof, m_connections.length);
			conn = m_connectionFactory(); // NOTE: may block
		}
		m_locks[fthis] = conn;
		m_lockCount[conn] = 1;
		if( cidx == size_t.max ){
			m_connections ~= conn;
			logDebug("Now got %d connections", m_connections.length);
		}
		auto ret = LockedConnection!Connection(this, conn);
		return ret;
	}
}

struct LockedConnection(Connection : EventedObject) {
	private {
		ConnectionPool!Connection m_pool;
		Task m_task;
	}
	
	Connection m_conn;

	alias m_conn this;

	private this(ConnectionPool!Connection pool, Connection conn)
	{
		m_pool = pool;
		m_conn = conn;
		m_task = Task.getThis();
	}

	this(this)
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_task);
			m_pool.m_lockCount[m_conn]++;
			logTrace("conn %s copy %d", cast(void*)m_conn, m_pool.m_lockCount[m_conn]);
		}
	}

	~this()
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_task);
			auto plc = m_conn in m_pool.m_lockCount;
			assert(plc !is null);
			//logTrace("conn %s destroy %d", cast(void*)m_conn, *plc-1);
			if( --*plc == 0 ){
				auto pl = m_task in m_pool.m_locks;
				assert(pl !is null);
				*pl = null;
				if( fthis ) m_conn.release();
				m_conn = null;
			}
		}
	}
}

/**
	Wraps an InputStream and automatically unlocks a locked connection as soon as all data has been
	read.
*/
class LockedInputStream(Connection : EventedObject) : InputStream {
	private {
		LockedConnection!Connection m_lock;
		InputStream m_stream;
	}


	this(LockedConnection!Connection conn, InputStream str)
	{
		m_lock = conn;
		m_stream = str;
	}

	@property bool empty() { return m_stream.empty; }

	@property ulong leastSize() { return m_stream.leastSize; }

	@property bool dataAvailableForRead() { return m_stream.dataAvailableForRead; }

	const(ubyte)[] peek() { return m_stream.peek(); }

	void read(ubyte[] dst)
	{
		m_stream.read(dst);
		if( this.empty ){
			LockedConnection!Connection unl;
			m_lock = unl;
		}
	}
}