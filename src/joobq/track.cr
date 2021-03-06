module JoobQ
  module Track
    extend self
    REDIS = JoobQ::REDIS

    def success(job, start)
      REDIS.pipelined do |pipe|
        pipe.command ["TS.ADD", "stats:#{job.queue}:success", "*", "#{latency(start)}", "ON_DUPLICATE", "FIRST"]
        pipe.lpush(Status::Completed.to_s, "#{job.jid}")
        pipe.lrem(Status::Busy.to_s, -1, "#{job.jid}")
      end
    end

    def processed(job, start)
      REDIS.pipelined do |pipe|
        pipe.command ["TS.ADD", "stats:processing", "*", "#{latency(start)}", "ON_DUPLICATE", "FIRST"]
        pipe.lrem(Status::Busy.to_s, 0, "#{job.jid}")
      end
    end

    def failure(job, start, ex)
      FailHandler.call job, latency(start), ex
    end

    private def latency(start)
      (Time.monotonic - start).milliseconds
    end
  end
end
