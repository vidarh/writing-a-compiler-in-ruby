class BasicSocket < IO
end

class Socket < BasicSocket
end

class IPSocket < BasicSocket
end

class TCPSocket < IPSocket
end

class UDPSocket < IPSocket
end

class UNIXSocket < BasicSocket
end
