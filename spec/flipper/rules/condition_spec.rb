require 'helper'

RSpec.describe Flipper::Rules::Condition do
  let(:feature_name) { "search" }

  describe "#eql?" do
    let(:rule) {
      Flipper::Rules::Condition.new(
        {"type" => "property", "value" => "plan"},
        {"type" => "operator", "value" => "eq"},
        {"type" => "string", "value" => "basic"}
      )
    }

    it "returns true if equal" do
      other_rule = Flipper::Rules::Condition.new(
        {"type" => "property", "value" => "plan"},
        {"type" => "operator", "value" => "eq"},
        {"type" => "string", "value" => "basic"}
      )
      expect(rule).to eql(other_rule)
      expect(rule == other_rule).to be(true)
    end

    it "returns false if not equal" do
      other_rule = Flipper::Rules::Condition.new(
        {"type" => "property", "value" => "plan"},
        {"type" => "operator", "value" => "eq"},
        {"type" => "string", "value" => "premium"}
      )
      expect(rule).not_to eql(other_rule)
      expect(rule == other_rule).to be(false)
    end

    it "returns false if not rule" do
      expect(rule).not_to eql(Object.new)
      expect(rule == Object.new).to be(false)
    end
  end

  describe "#matches?" do
    context "eq" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "plan"},
          {"type" => "operator", "value" => "eq"},
          {"type" => "string", "value" => "basic"}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "plan" => "basic",
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does not match" do
        actor = Flipper::Actor.new("User;1", {
          "plan" => "premium",
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "neq" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "plan"},
          {"type" => "operator", "value" => "neq"},
          {"type" => "string", "value" => "basic"}
        )
      }

      it "returns true when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "plan" => "premium",
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does match" do
        actor = Flipper::Actor.new("User;1", {
          "plan" => "basic",
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "gt" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "age"},
          {"type" => "operator", "value" => "gt"},
          {"type" => "integer", "value" => 20}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 21,
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 20,
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "gte" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "age"},
          {"type" => "operator", "value" => "gte"},
          {"type" => "integer", "value" => 20}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 20,
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 19,
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "lt" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "age"},
          {"type" => "operator", "value" => "lt"},
          {"type" => "integer", "value" => 21}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 20,
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 21,
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "lt with rand type" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "random", "value" => 100},
          {"type" => "operator", "value" => "lt"},
          {"type" => "integer", "value" => 25}
        )
      }

      it "returns true when property matches" do
        results = []
        (1..1000).to_a.each do |n|
          actor = Flipper::Actor.new("User;#{n}")
          results << rule.matches?(feature_name, actor)
        end

        enabled, disabled = results.partition { |r| r }
        expect(enabled.size).to be_within(30).of(250)
      end
    end

    context "lte" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "age"},
          {"type" => "operator", "value" => "lte"},
          {"type" => "integer", "value" => 21}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 21,
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 22,
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "in" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "age"},
          {"type" => "operator", "value" => "in"},
          {"type" => "array", "value" => [20, 21, 22]}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 21,
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 10,
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "nin" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "age"},
          {"type" => "operator", "value" => "nin"},
          {"type" => "array", "value" => [20, 21, 22]}
        )
      }

      it "returns true when property matches" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 10,
        })
        expect(rule.matches?(feature_name, actor)).to be(true)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1", {
          "age" => 20,
        })
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end

    context "percentage" do
      let(:rule) {
        Flipper::Rules::Condition.new(
          {"type" => "property", "value" => "flipper_id"},
          {"type" => "operator", "value" => "percentage"},
          {"type" => "integer", "value" => 25}
        )
      }

      it "returns true when property matches" do
        results = []
        (1..1000).to_a.each do |n|
          actor = Flipper::Actor.new("User;#{n}")
          results << rule.matches?(feature_name, actor)
        end

        enabled, disabled = results.partition { |r| r }
        expect(enabled.size).to be_within(10).of(250)
      end

      it "returns false when property does NOT match" do
        actor = Flipper::Actor.new("User;1")
        expect(rule.matches?(feature_name, actor)).to be(false)
      end
    end
  end
end