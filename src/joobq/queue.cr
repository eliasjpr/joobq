module JoobQ
  class Queue(T)
    private TIMEOUT = 2

    getter redis : Redis::PooledClient = JoobQ.redis
    getter name : String
    getter total_workers : Int32
    getter workers : Array(Worker(T))
    getter jobs : String = T.to_s
    getter terminate_channel = Channel(Nil).new
    private getter? stopped = false

    def initialize(@name : String, @total_workers : Int32)
      @workers = Array(Worker(T)).new(@total_workers)
      create_workers
    end

    def start
      @stopped = false
      workers.each &.run
    end

    def get_next : T?
      # Add to BUSY queue so we can later monitor busy jobs and be able to
      # gracefully terminate jobs processing them
      if job_id = redis.brpoplpush(name, Status::Busy.to_s, TIMEOUT)
        return self.[job_id]? if !job_id.is_a? Int64
      end
    end

    def push(job : String)
      job = T.from_json(job)
      set_job job
      redis.rpush name, "#{job.jid}"
    end

    def push(job : T)
      set_job job
      redis.rpush name, "#{job.jid}"
    end

    def set_job(job)
      redis.setex "jobs:#{job.jid}", job.expires, job.to_json
    end

    def []?(job_id) : T?
      job_data = redis.get("jobs:#{job_id}")
      T.from_json job_data.as(String) if job_data && !job_data.is_a? Int64
    rescue ex 
      
    end

    def size
      redis.llen(name)
    end

    def status
      case
      when !size.zero? then "Running"
      when size.zero?  then "Done"
      else                  "Awaiting"
      end
    end

    def running_workers
      workers.count
    end

    def clear
      redis.del name
    end

    def stop!
      @stopped = true
      terminate.send nil
    end

    def terminate(worker : Worker(T))
      Log.error &.emit("Terminating Worker!", Queue: name, Worker_Id: worker.wid)
      workers.delete worker
    end

    def restart(worker : Worker(T), ex : Exception)
      terminate worker
      return if stopped?

      Log.error &.emit("Restarting Worker!", Queue: name, Worker_Id: worker.wid)
      worker = create_worker
      workers << worker
      worker.run
      worker
    end

    private def create_workers
      total_workers.times do |n|
        workers << create_worker
      end
    end

    private def create_worker
      Worker(T).new workers.size, terminate_channel, self
    end
  end
end
