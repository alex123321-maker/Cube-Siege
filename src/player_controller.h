#pragma once

#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

class PlayerController : public CharacterBody3D {
    GDCLASS(PlayerController, CharacterBody3D);

private:
    float speed = 7.0f;
    float dash_speed = 18.0f;
    float dash_duration = 0.2f;
    float dash_cooldown = 2.5f;

    float current_health = 100.0f;
    float max_health = 100.0f;

    bool is_dashing = false;
    float dash_timer = 0.0f;
    float dash_cooldown_timer = 0.0f;

    bool is_parrying = false;
    float parry_timer = 0.0f;
    float parry_cooldown_timer = 0.0f;

    Vector3 dash_direction = Vector3(0, 0, 0);

protected:
    static void _bind_methods();

public:
    PlayerController();
    ~PlayerController();

    void _ready() override;
    void _physics_process(double delta) override;

    // Movement & Twin-stick aim
    void handle_movement(double delta);
    void handle_aim();

    // Combat actions
    void perform_dash();
    void perform_parry();
    void take_damage(float damage);

    // Getters & Setters for Godot Editor inspection
    void set_speed(float p_speed);
    float get_speed() const;

    void set_dash_speed(float p_dash_speed);
    float get_dash_speed() const;

    void set_max_health(float p_max_health);
    float get_max_health() const;

    float get_current_health() const;
    bool get_is_dashing() const;
    bool get_is_parrying() const;
};

} // namespace godot
