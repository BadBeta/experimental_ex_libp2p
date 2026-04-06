defmodule ExLibp2p.OTP.TaskTrackerTest do
  use ExUnit.Case, async: true

  alias ExLibp2p.{Node, PeerId}
  alias ExLibp2p.OTP.TaskTracker

  @peer_a PeerId.new!("12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN")
  @peer_b PeerId.new!("12D3KooWRPmBBCBTuGh1cnUuFVr35GYnm4bRXYsSB94TXJLAg4mA")

  setup do
    {:ok, node} =
      Node.start_link(
        native_module: ExLibp2p.Native.Mock,
        listen_addrs: ["/ip4/127.0.0.1/tcp/0"]
      )

    {:ok, tracker} = TaskTracker.start_link(node: node)

    %{node: node, tracker: tracker}
  end

  describe "dispatch/4" do
    test "tracks a dispatched task", %{tracker: tracker} do
      {:ok, task_id} = TaskTracker.dispatch(tracker, @peer_a, :my_worker, {:process, "data"})

      assert is_binary(task_id)
      assert {:ok, task} = TaskTracker.get(tracker, task_id)
      assert task.peer_id == @peer_a
      assert task.target == :my_worker
      assert task.message == {:process, "data"}
      assert task.status == :pending
    end

    test "assigns unique task IDs", %{tracker: tracker} do
      {:ok, id1} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job1)
      {:ok, id2} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job2)
      refute id1 == id2
    end
  end

  describe "complete/2" do
    test "marks task as completed", %{tracker: tracker} do
      {:ok, task_id} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job)
      :ok = TaskTracker.complete(tracker, task_id)

      assert {:ok, task} = TaskTracker.get(tracker, task_id)
      assert task.status == :completed
    end

    test "returns error for unknown task", %{tracker: tracker} do
      assert {:error, :not_found} = TaskTracker.complete(tracker, "nonexistent")
    end
  end

  describe "fail/3" do
    test "marks task as failed with reason", %{tracker: tracker} do
      {:ok, task_id} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job)
      :ok = TaskTracker.fail(tracker, task_id, :timeout)

      assert {:ok, task} = TaskTracker.get(tracker, task_id)
      assert task.status == {:failed, :timeout}
    end
  end

  describe "pending_for_peer/2" do
    test "returns pending tasks for a peer", %{tracker: tracker} do
      {:ok, _} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job1)
      {:ok, _} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job2)
      {:ok, id3} = TaskTracker.dispatch(tracker, @peer_b, :worker, :job3)
      TaskTracker.complete(tracker, id3)

      pending = TaskTracker.pending_for_peer(tracker, @peer_a)
      assert length(pending) == 2
      assert Enum.all?(pending, &(&1.status == :pending))
      assert Enum.all?(pending, &(&1.peer_id == @peer_a))
    end

    test "returns empty list for unknown peer", %{tracker: tracker} do
      assert TaskTracker.pending_for_peer(tracker, @peer_b) == []
    end
  end

  describe "peer disappearance" do
    test "notifies subscriber when peer with pending tasks disconnects", %{
      node: node,
      tracker: tracker
    } do
      TaskTracker.subscribe(tracker)

      {:ok, _} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job1)
      {:ok, _} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job2)

      # Simulate peer disconnection event
      raw_event =
        {:connection_closed, to_string(@peer_a), 0, :keep_alive_timeout}

      send(node, {:libp2p_event, raw_event})

      assert_receive {:task_tracker, :peer_lost, peer_id, orphaned_tasks}, 1000
      assert peer_id == @peer_a
      assert length(orphaned_tasks) == 2
      assert Enum.all?(orphaned_tasks, &(&1.status == {:failed, :peer_lost}))
    end

    test "does not notify when peer with no pending tasks disconnects", %{
      node: node,
      tracker: tracker
    } do
      TaskTracker.subscribe(tracker)

      # No tasks dispatched to @peer_a
      raw_event =
        {:connection_closed, to_string(@peer_a), 0, :keep_alive_timeout}

      send(node, {:libp2p_event, raw_event})

      refute_receive {:task_tracker, :peer_lost, _, _}, 200
    end

    test "does not notify for completed tasks when peer disconnects", %{
      node: node,
      tracker: tracker
    } do
      TaskTracker.subscribe(tracker)

      {:ok, task_id} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job)
      TaskTracker.complete(tracker, task_id)

      raw_event =
        {:connection_closed, to_string(@peer_a), 0, :keep_alive_timeout}

      send(node, {:libp2p_event, raw_event})

      refute_receive {:task_tracker, :peer_lost, _, _}, 200
    end
  end

  describe "all_pending/1" do
    test "returns all pending tasks across all peers", %{tracker: tracker} do
      {:ok, _} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job1)
      {:ok, _} = TaskTracker.dispatch(tracker, @peer_b, :worker, :job2)
      {:ok, id3} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job3)
      TaskTracker.complete(tracker, id3)

      pending = TaskTracker.all_pending(tracker)
      assert length(pending) == 2
    end
  end

  describe "cleanup/1" do
    test "removes completed and failed tasks", %{tracker: tracker} do
      {:ok, id1} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job1)
      {:ok, id2} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job2)
      {:ok, _id3} = TaskTracker.dispatch(tracker, @peer_a, :worker, :job3)

      TaskTracker.complete(tracker, id1)
      TaskTracker.fail(tracker, id2, :error)

      count = TaskTracker.cleanup(tracker)
      assert count == 2

      # Only pending task remains
      assert {:error, :not_found} = TaskTracker.get(tracker, id1)
      assert {:error, :not_found} = TaskTracker.get(tracker, id2)
    end
  end
end
