require "ood_core/job/adapters/lsf"
require "ood_core/job/adapters/lsf/batch"
require "timecop"

describe OodCore::Job::Adapters::Lsf::Batch do
  subject(:batch) { described_class.new() }

  #TODO: consider using contexts http://betterspecs.org/#contexts
  describe "#parse_bsub_output" do
    # parse bsubmit output
    it "should correctly parse bsub output" do
      expect(batch.parse_bsub_output "Job <542935> is submitted to queue <short>.\n").to eq "542935"
    end
  end

  describe "#parse_bjobs_output" do
    it "handles nil" do
      expect(batch.parse_bjobs_output nil).to eq []
    end

    it "handles no jobs in output" do
      expect(batch.parse_bjobs_output "No job found\n").to eq []
    end

    it "raises exception for unexpected columns" do
      # I added ANOTHER_COLUMN to the end of this
      output = <<-OUTPUT
JOBID   USER    STAT  QUEUE
542935  efranz  RUN   short
      OUTPUT
      expect { batch.parse_bjobs_output output }.to raise_error(OodCore::Job::Adapters::Lsf::Batch::Error)
    end

    it "parses output for one job" do
      output = <<-OUTPUT
JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME  PROJ_NAME CPU_USED MEM SWAP PIDS START_TIME FINISH_TIME
542935  efranz  RUN   short      foobar02.osc.edu compute013  foo        03/31-14:46:42 default    000:00:00.00 2      32     25156 03/31-14:46:44 -
      OUTPUT
      expect(batch.parse_bjobs_output(output)).to eq([{
        id: "542935",
        user: "efranz",
        status: "RUN",
        queue: "short",
        from_host: "foobar02.osc.edu",
        exec_host: "compute013",
        name: "foo",
        submit_time: "03/31-14:46:42",
        project: "default",
        cpu_used: "000:00:00.00",
        mem:"2",
        swap:"32",
        pids:"25156",
        start_time: "03/31-14:46:44",
        finish_time: nil
       }])
    end

    it "parses output for two jobs" do
      output = <<-OUTPUT
JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME  PROJ_NAME CPU_USED MEM SWAP PIDS START_TIME FINISH_TIME
542935  efranz  RUN   short      foobar02.osc.edu compute013  foo        03/31-14:46:42 default    000:00:00.00 2      32     25156 03/31-14:46:44 -
542936  efranz  RUN   short      foobar02.osc.edu compute014  bar        03/31-14:46:42 default    000:00:00.00 2      32     25156 03/31-14:46:44 -
      OUTPUT
      expect(batch.parse_bjobs_output(output)).to eq([{
        id: "542935",
        user: "efranz",
        status: "RUN",
        queue: "short",
        from_host: "foobar02.osc.edu",
        exec_host: "compute013",
        name: "foo",
        submit_time: "03/31-14:46:42",
        project: "default",
        cpu_used: "000:00:00.00",
        mem:"2",
        swap:"32",
        pids:"25156",
        start_time: "03/31-14:46:44",
        finish_time: nil
       },{
        id: "542936",
        user: "efranz",
        status: "RUN",
        queue: "short",
        from_host: "foobar02.osc.edu",
        exec_host: "compute014",
        name: "bar",
        submit_time: "03/31-14:46:42",
        project: "default",
        cpu_used: "000:00:00.00",
        mem:"2",
        swap:"32",
        pids:"25156",
        start_time: "03/31-14:46:44",
        finish_time: nil

       }])
    end

    it "parses output for piped script with no jobname" do
      output = <<-OUTPUT
JOBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME  PROJ_NAME CPU_USED MEM SWAP PIDS START_TIME FINISH_TIME
542945  efranz  DONE  short      foobar02.osc.edu compute013  #!/bin/bash;#;#BSUB -q short # queue;#BSUB -e myjob.%J.err;#BSUB -o myjob.%J.out; echo "Hello world, I am in $PWD";sleep 30;echo "Goodbye, world!" 03/31-19:24:57 default    000:00:00.03 2      32     9389 03/31-19:24:59 03/31-19:25:29
OUTPUT
      expect(batch.parse_bjobs_output(output)).to eq([{
        id: "542945",
        user: "efranz",
        status: "DONE",
        queue: "short",
        from_host: "foobar02.osc.edu",
        exec_host: "compute013",
        name: "#!/bin/bash;#;#BSUB -q short # queue;#BSUB -e myjob.%J.err;#BSUB -o myjob.%J.out; echo \"Hello world, I am in $PWD\";sleep 30;echo \"Goodbye, world!\"",
        submit_time: "03/31-19:24:57",
        project: "default",
        cpu_used: "000:00:00.03",
        mem:"2",
        swap:"32",
        pids:"9389",
        start_time: "03/31-19:24:59",
        finish_time: "03/31-19:25:29"
       }])
    end
  end

  describe "#get_jobs" do
    it "calls bjobs with default args when id not specified" do
      expect(batch).to receive(:call).with("bjobs", *batch.bjobs_default_args)
      batch.get_jobs
    end
  end

  describe "#default_env" do
    subject(:batch) { described_class.new(config).default_env }

    context "when {}" do
      let(:config) { {}  }
      it { is_expected.to eq({}) }
    end

    context "when bindir set" do
      let(:config) { { bindir: "/opt/lsf/8.3/bin" } }
      it { is_expected.to eq({"LSF_BINDIR" => "/opt/lsf/8.3/bin"}) }
    end

    context "when envdir set" do
      let(:config) { { envdir: "/opt/lsf/conf" } }
      it { is_expected.to eq({"LSF_ENVDIR" => "/opt/lsf/conf"}) }
    end

    context "when bindir, libdir, envdir, and serverdir set" do
      let(:config) {
        {
          bindir: "/opt/lsf/8.3/bin",
          libdir: "/opt/lsf/8.3/lib",
          envdir: "/opt/lsf/conf",
          serverdir: "/opt/lsf/8.3/etc"
        }
      }

      it { is_expected.to eq(
        {
          "LSF_BINDIR" => "/opt/lsf/8.3/bin",
          "LSF_LIBDIR" => "/opt/lsf/8.3/lib",
          "LSF_ENVDIR" =>"/opt/lsf/conf",
          "LSF_SERVERDIR" =>"/opt/lsf/8.3/etc"
        }
      )}
    end
  end
end