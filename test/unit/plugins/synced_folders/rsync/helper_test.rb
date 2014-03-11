require_relative "../../../base"

require "vagrant/util/platform"

require Vagrant.source_root.join("plugins/synced_folders/rsync/helper")

describe VagrantPlugins::SyncedFolderRSync::RsyncHelper do
  include_context "unit"

  let(:iso_env) do
    # We have to create a Vagrantfile so there is a root path
    env = isolated_environment
    env.vagrantfile("")
    env.create_vagrant_env
  end

  let(:guest)   { double("guest") }
  let(:machine) { iso_env.machine(iso_env.machine_names[0], :dummy) }

  subject { described_class }

  before do
    machine.stub(guest: guest)

    # Don't do all the crazy Cygwin stuff
    Vagrant::Util::Platform.stub(:cygwin_path) do |path, **opts|
      path
    end
  end

  describe "#rsync_single" do
    let(:result) { Vagrant::Util::Subprocess::Result.new(0, "", "") }

    let(:ssh_info) {{
      private_key_path: [],
    }}
    let(:opts)      {{
      hostpath: "/foo",
    }}
    let(:ui)        { machine.ui }

    before do
      Vagrant::Util::Subprocess.stub(execute: result)

      guest.stub(capability?: false)
    end

    it "doesn't raise an error if it succeeds" do
      subject.rsync_single(machine, ssh_info, opts)
    end

    it "doesn't call cygwin_path on non-Windows" do
      Vagrant::Util::Platform.stub(windows?: false)
      Vagrant::Util::Platform.should_not_receive(:cygwin_path)
      subject.rsync_single(machine, ssh_info, opts)
    end

    it "calls cygwin_path on Windows" do
      Vagrant::Util::Platform.stub(windows?: true)
      Vagrant::Util::Platform.should_receive(:cygwin_path).and_return("foo")

      Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
        expect(args[args.length - 3]).to eql("foo/")
      end

      subject.rsync_single(machine, ssh_info, opts)
    end

    it "raises an error if the exit code is non-zero" do
      Vagrant::Util::Subprocess.stub(
        execute: Vagrant::Util::Subprocess::Result.new(1, "", ""))

      expect {subject.rsync_single(machine, ssh_info, opts) }.
        to raise_error(Vagrant::Errors::RSyncError)
    end

    context "host and guest paths" do
      it "syncs the hostpath to the guest path" do
        opts[:hostpath] = "/foo"
        opts[:guestpath] = "/bar"

        Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
          expected = Vagrant::Util::Platform.fs_real_path("/foo").to_s
          expect(args[args.length - 3]).to eql("#{expected}/")
          expect(args[args.length - 2]).to include("/bar")
        end

        subject.rsync_single(machine, ssh_info, opts)
      end

      it "expands the hostpath relative to the root path" do
        opts[:hostpath] = "foo"
        opts[:guestpath] = "/bar"

        hostpath_expanded = File.expand_path(opts[:hostpath], machine.env.root_path)

        Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
          expect(args[args.length - 3]).to eql("#{hostpath_expanded}/")
          expect(args[args.length - 2]).to include("/bar")
        end

        subject.rsync_single(machine, ssh_info, opts)
      end
    end

    it "executes within the root path" do
      Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
        expect(args.last).to be_kind_of(Hash)

        opts = args.last
        expect(opts[:workdir]).to eql(machine.env.root_path.to_s)
      end

      subject.rsync_single(machine, ssh_info, opts)
    end

    it "executes the rsync_pre capability first if it exists" do
      guest.should_receive(:capability?).with(:rsync_pre).and_return(true)
      guest.should_receive(:capability).with(:rsync_pre, opts).ordered
      Vagrant::Util::Subprocess.should_receive(:execute).ordered.and_return(result)

      subject.rsync_single(machine, ssh_info, opts)
    end

    context "excluding files" do
      it "excludes files if given as a string" do
        opts[:exclude] = "foo"

        Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
          index = args.find_index("foo")
          expect(index).to be > 0
          expect(args[index-1]).to eql("--exclude")
        end

        subject.rsync_single(machine, ssh_info, opts)
      end

      it "excludes multiple files" do
        opts[:exclude] = ["foo", "bar"]

        Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
          index = args.find_index("foo")
          expect(index).to be > 0
          expect(args[index-1]).to eql("--exclude")

          index = args.find_index("bar")
          expect(index).to be > 0
          expect(args[index-1]).to eql("--exclude")
        end

        subject.rsync_single(machine, ssh_info, opts)
      end
    end

    context "custom arguments" do
      it "uses the default arguments if not given" do
        Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
          expect(args[1]).to eq("--verbose")
          expect(args[2]).to eq("--archive")
          expect(args[3]).to eq("--delete")

          expected = Vagrant::Util::Platform.fs_real_path("/foo").to_s
          expect(args[args.length - 3]).to eql("#{expected}/")
        end

        subject.rsync_single(machine, ssh_info, opts)
      end

      it "uses the custom arguments if given" do
        opts[:args] = ["--verbose", "-z"]

        Vagrant::Util::Subprocess.should_receive(:execute).with do |*args|
          expect(args[1]).to eq("--verbose")
          expect(args[2]).to eq("-z")

          expected = Vagrant::Util::Platform.fs_real_path("/foo").to_s
          expect(args[args.length - 3]).to eql("#{expected}/")
        end

        subject.rsync_single(machine, ssh_info, opts)
      end
    end
  end
end
