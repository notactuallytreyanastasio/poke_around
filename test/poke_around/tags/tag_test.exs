defmodule PokeAround.Tags.TagTest do
  use PokeAround.DataCase, async: true

  alias PokeAround.Tags.Tag

  describe "slugify/1" do
    test "lowercases text" do
      assert Tag.slugify("UPPERCASE") == "uppercase"
    end

    test "replaces spaces with hyphens" do
      assert Tag.slugify("hello world") == "hello-world"
    end

    test "removes special characters" do
      assert Tag.slugify("hello@world!") == "hello-world"
    end

    test "collapses multiple hyphens" do
      assert Tag.slugify("hello---world") == "hello-world"
    end

    test "trims leading and trailing hyphens" do
      assert Tag.slugify("-hello-") == "hello"
    end

    test "handles complex tag names" do
      assert Tag.slugify("JavaScript & TypeScript!") == "javascript-typescript"
    end

    test "handles numbers" do
      assert Tag.slugify("Web 3.0") == "web-3-0"
    end

    test "handles empty string" do
      assert Tag.slugify("") == ""
    end
  end

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = Tag.changeset(%Tag{}, %{name: "Test", slug: "test"})

      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Tag.changeset(%Tag{}, %{slug: "test"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "invalid without slug" do
      changeset = Tag.changeset(%Tag{}, %{name: "Test"})

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "accepts usage_count" do
      changeset = Tag.changeset(%Tag{}, %{name: "Test", slug: "test", usage_count: 10})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :usage_count) == 10
    end
  end
end
